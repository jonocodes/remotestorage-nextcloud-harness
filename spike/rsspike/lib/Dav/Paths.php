<?php

declare(strict_types=1);

namespace OCA\RsSpike\Dav;

use OCA\RsSpike\AppInfo\Application;
use Sabre\HTTP\RequestInterface;

final class Paths {
	/**
	 * Splits the request into the user and the remoteStorage path below the
	 * storage root. Uses the raw URL, not Sabre's getPath(): getPath() strips
	 * the trailing slash, and in remoteStorage that slash is what makes a path
	 * a folder.
	 *
	 * @return array{uid:string, rel:string, module:string, folder:bool}|null
	 */
	public static function match(RequestInterface $request): ?array {
		$path = rawurldecode((string)parse_url($request->getUrl(), PHP_URL_PATH));
		$pattern = '#/remote\.php/dav/files/([^/]+)/' . preg_quote(Application::ROOT, '#') . '(/.*)?$#';
		if (!preg_match($pattern, $path, $m)) {
			return null;
		}
		$rel = ($m[2] ?? '') === '' ? '/' : $m[2];
		$segments = explode('/', ltrim($rel, '/'), 2);
		return [
			'uid' => $m[1],
			'rel' => $rel,
			'module' => $segments[0],
			'folder' => str_ends_with($rel, '/'),
		];
	}
}
