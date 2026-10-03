<?php

declare(strict_types=1);

namespace OCA\RsSpike\Dav;

use OCA\RsSpike\AppInfo\Application;
use OCP\IConfig;
use OCP\IUserManager;
use OCP\IUserSession;
use Sabre\DAV\Auth\Backend\BackendInterface;
use Sabre\HTTP\RequestInterface;
use Sabre\HTTP\ResponseInterface;

/**
 * S1: accepts the app's own bearer token; S4: lets anonymous GET/HEAD of
 * documents under <root>/public/ through as a read-only, public-only login.
 * The spike's single token lives in app config (token, user, scope).
 */
class TokenAuth implements BackendInterface {
	public function __construct(
		private IConfig $config,
		private IUserManager $userManager,
		private IUserSession $userSession,
	) {
	}

	public function check(RequestInterface $request, ResponseInterface $response) {
		$auth = (string)$request->getHeader('Authorization');
		if (str_starts_with($auth, 'Bearer ')) {
			$expected = $this->config->getAppValue(Application::APP_ID, 'token', '');
			if ($expected === '' || !hash_equals($expected, substr($auth, 7))) {
				return [false, 'not an rsspike token'];
			}
			$uid = $this->config->getAppValue(Application::APP_ID, 'user', '');
			$scopes = self::parseScopes($this->config->getAppValue(Application::APP_ID, 'scope', ''));
			return $this->login($uid, $scopes, false);
		}

		if ($auth === '' && in_array($request->getMethod(), ['GET', 'HEAD'], true)) {
			$m = Paths::match($request);
			if ($m !== null && $m['module'] === 'public' && !$m['folder']) {
				return $this->login($m['uid'], ['public' => 'r'], true);
			}
		}

		return [false, 'no rsspike credentials'];
	}

	public function challenge(RequestInterface $request, ResponseInterface $response): void {
	}

	/** @return array<string,string> */
	private static function parseScopes(string $scope): array {
		$scopes = [];
		foreach (preg_split('/\s+/', trim($scope)) ?: [] as $item) {
			if (preg_match('/^([a-z0-9_*-]+):(rw|r)$/i', $item, $m)) {
				$scopes[$m[1]] = $m[2];
			}
		}
		return $scopes;
	}

	private function login(string $uid, array $scopes, bool $publicOnly) {
		$user = $this->userManager->get($uid);
		if ($user === null) {
			return [false, 'unknown user'];
		}
		// Request-only login: nothing is written to the session, no cookie.
		$this->userSession->setVolatileActiveUser($user);
		\OC_Util::setupFS($uid);
		RequestState::$uid = $uid;
		RequestState::$scopes = $scopes;
		RequestState::$publicOnly = $publicOnly;
		return [true, 'principals/users/' . $uid];
	}
}
