<?php

declare(strict_types=1);

namespace OCA\RsSpike\Listener;

use OCA\DAV\Events\SabrePluginAddEvent;
use OCA\RsSpike\Dav\RsPlugin;
use OCP\EventDispatcher\Event;
use OCP\EventDispatcher\IEventListener;

/** @template-implements IEventListener<SabrePluginAddEvent> */
class PluginAddListener implements IEventListener {
	public function handle(Event $event): void {
		if ($event instanceof SabrePluginAddEvent) {
			$event->getServer()->addPlugin(new RsPlugin());
		}
	}
}
