<?php

declare(strict_types=1);

namespace OCA\RsSpike\WellKnown;

use OCA\RsSpike\AppInfo\Application;
use OCP\Http\WellKnown\IHandler;
use OCP\Http\WellKnown\IRequestContext;
use OCP\Http\WellKnown\IResponse;
use OCP\Http\WellKnown\JrdResponse;
use OCP\IURLGenerator;
use OCP\IUserManager;

class WebFingerHandler implements IHandler {
	public function __construct(
		private IUserManager $userManager,
		private IURLGenerator $urlGenerator,
	) {
	}

	public function handle(string $service, IRequestContext $context, ?IResponse $previousResponse): ?IResponse {
		if ($service !== 'webfinger') {
			return $previousResponse;
		}
		$request = $context->getHttpRequest();
		$resource = (string)$request->getParam('resource', '');
		if (!preg_match('/^acct:([^@]+)@(.+)$/', $resource, $m)
			|| strcasecmp($m[2], $request->getServerHost()) !== 0) {
			return $previousResponse;
		}
		$user = $this->userManager->get($m[1]);
		if ($user === null) {
			return $previousResponse;
		}
		$jrd = $previousResponse instanceof JrdResponse ? $previousResponse : new JrdResponse($resource);
		$jrd->addLink(
			'http://tools.ietf.org/id/draft-dejong-remotestorage',
			null,
			$this->urlGenerator->getAbsoluteURL(
				'/remote.php/dav/files/' . rawurlencode($user->getUID()) . '/' . Application::ROOT
			),
			[],
			[
				'http://remotestorage.io/spec/version' => 'draft-dejong-remotestorage-22',
				'http://tools.ietf.org/html/rfc6749#section-4.2' =>
					$this->urlGenerator->getAbsoluteURL('/index.php/apps/rsspike/oauth'),
				'http://tools.ietf.org/html/rfc7233' => 'GET',
			],
		);
		return new CorsJrdResponse($jrd);
	}
}
