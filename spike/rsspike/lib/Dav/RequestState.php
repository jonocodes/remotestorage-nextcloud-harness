<?php

declare(strict_types=1);

namespace OCA\RsSpike\Dav;

/**
 * What TokenAuth decided about the current request; read by RsPlugin.
 * One PHP request = one DAV request, so static state is enough for a spike.
 */
final class RequestState {
	public static ?string $uid = null;
	/** @var array<string,string> module => 'r' | 'rw' ('*' for all) */
	public static array $scopes = [];
	public static bool $publicOnly = false;
}
