<?php

declare(strict_types=1);

namespace OCA\RsSpike\Dav;

use OCA\DAV\Connector\Sabre\File;
use OCA\DAV\Connector\Sabre\Node;
use Sabre\DAV\Exception\Forbidden;
use Sabre\DAV\Exception\MethodNotAllowed;
use Sabre\DAV\Exception\NotFound;
use Sabre\DAV\ICollection;
use Sabre\DAV\Server;
use Sabre\DAV\ServerPlugin;
use Sabre\HTTP\RequestInterface;
use Sabre\HTTP\ResponseInterface;
use Sabre\HTTP\Sapi;

/**
 * The gap-filling WebDAV plugin. CORS for requests under the storage root;
 * everything else only for requests TokenAuth logged in.
 */
class RsPlugin extends ServerPlugin {
	private const METHODS = 'GET, HEAD, PUT, DELETE, OPTIONS';
	private const ALLOW_HEADERS = 'Authorization, Content-Type, Content-Length, If-Match, If-None-Match, Origin, Range';
	private const EXPOSE_HEADERS = 'ETag, Content-Type, Content-Length, Content-Range, Last-Modified';

	private Server $server;

	public function initialize(Server $server): void {
		$this->server = $server;
		// Before core's AnonymousOptionsPlugin (9) and the auth plugin (10).
		$server->on('beforeMethod:*', [$this, 'cors'], 5);
		// After auth (10): enforce scope for our logins only.
		$server->on('beforeMethod:*', [$this, 'enforceScope'], 20);
		// Before Sabre's CorePlugin GET handler (100).
		$server->on('method:GET', [$this, 'folderGet'], 50);
	}

	public function cors(RequestInterface $request, ResponseInterface $response) {
		$origin = $request->getHeader('Origin');
		if (empty($origin) || Paths::match($request) === null
			|| $response->hasHeader('Access-Control-Allow-Origin')) {
			return;
		}
		// Actual requests: only bearer-token or anonymous ones (including bad
		// tokens, so the app can see the 401). Basic-auth requests stay
		// exactly as core answers them. Preflights carry no credentials.
		$auth = (string)$request->getHeader('Authorization');
		if ($auth !== '' && !str_starts_with($auth, 'Bearer ')) {
			return;
		}
		// Bearer tokens, never cookies: "*" means browsers will not send credentials.
		$response->setHeader('Access-Control-Allow-Origin', '*');
		$response->setHeader('Access-Control-Expose-Headers', self::EXPOSE_HEADERS);
		if ($request->getMethod() === 'OPTIONS' && empty($request->getHeader('Authorization'))) {
			$response->setHeader('Access-Control-Allow-Methods', self::METHODS);
			$response->setHeader('Access-Control-Allow-Headers', self::ALLOW_HEADERS);
			$response->setHeader('Access-Control-Max-Age', '600');
			$response->setStatus(204);
			Sapi::sendResponse($response);
			return false;
		}
	}

	public function enforceScope(RequestInterface $request, ResponseInterface $response): void {
		if (RequestState::$uid === null) {
			return;
		}
		$m = Paths::match($request);
		if ($m === null || $m['uid'] !== RequestState::$uid) {
			throw new Forbidden('outside the remoteStorage root');
		}
		$method = $request->getMethod();
		if (!in_array($method, ['GET', 'HEAD', 'PUT', 'DELETE'], true)) {
			throw new MethodNotAllowed($method . ' is not part of remoteStorage');
		}
		$write = in_array($method, ['PUT', 'DELETE'], true);
		$isPublicDocument = $m['module'] === 'public' && !$m['folder'];
		if (RequestState::$publicOnly) {
			if ($write || !$isPublicDocument) {
				throw new Forbidden('public access is read-only and documents-only');
			}
			return;
		}
		$level = RequestState::$scopes['*'] ?? RequestState::$scopes[$m['module']] ?? null;
		if ($m['rel'] === '/' && !isset(RequestState::$scopes['*'])) {
			$level = null;
		}
		if ($level === null || ($write && $level !== 'rw')) {
			throw new Forbidden('token scope does not cover ' . $m['rel']);
		}
	}

	public function folderGet(RequestInterface $request, ResponseInterface $response) {
		if (RequestState::$uid === null) {
			return;
		}
		$m = Paths::match($request);
		$node = $this->server->tree->getNodeForPath($request->getPath());
		if (!$node instanceof ICollection) {
			if ($m !== null && $m['folder']) {
				throw new NotFound('not a folder');
			}
			return;
		}
		// A path without a trailing slash names a document, never a folder.
		if ($m === null || !$m['folder']) {
			throw new NotFound('no document at this path');
		}
		// Defence in depth: public-only logins never see listings.
		if (RequestState::$publicOnly) {
			throw new Forbidden('public folder listings are not readable without a token');
		}
		$items = [];
		foreach ($node->getChildren() as $child) {
			if (!$child instanceof Node) {
				continue;
			}
			$etag = trim($child->getETag(), '"');
			if ($child instanceof ICollection) {
				$items[$child->getName() . '/'] = ['ETag' => $etag];
			} elseif ($child instanceof File) {
				$items[$child->getName()] = [
					'ETag' => $etag,
					'Content-Type' => $child->getContentType(),
					'Content-Length' => $child->getSize(),
					'Last-Modified' => gmdate('D, d M Y H:i:s \G\M\T', (int)$child->getLastModified()),
				];
			}
		}
		$body = json_encode([
			'@context' => 'http://remotestorage.io/spec/folder-description',
			'items' => (object)$items,
		], JSON_UNESCAPED_SLASHES);
		$response->setStatus(200);
		$response->setHeader('Content-Type', 'application/ld+json');
		if ($node instanceof Node) {
			$response->setHeader('ETag', $node->getETag());
		}
		$response->setHeader('Cache-Control', 'no-cache');
		$response->setBody($body);
		return false;
	}
}
