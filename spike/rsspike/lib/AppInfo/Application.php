<?php

declare(strict_types=1);

namespace OCA\RsSpike\AppInfo;

use OCA\DAV\Events\SabrePluginAddEvent;
use OCA\DAV\Events\SabrePluginAuthInitEvent;
use OCA\RsSpike\Listener\AuthInitListener;
use OCA\RsSpike\Listener\PluginAddListener;
use OCA\RsSpike\WellKnown\WebFingerHandler;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;

class Application extends App implements IBootstrap {
	public const APP_ID = 'rsspike';
	/** Storage root inside the user's files. */
	public const ROOT = 'remotestorage';

	public function __construct() {
		parent::__construct(self::APP_ID);
	}

	public function register(IRegistrationContext $context): void {
		$context->registerEventListener(SabrePluginAuthInitEvent::class, AuthInitListener::class);
		$context->registerEventListener(SabrePluginAddEvent::class, PluginAddListener::class);
		$context->registerWellKnownHandler(WebFingerHandler::class);
	}

	public function boot(IBootContext $context): void {
	}
}
