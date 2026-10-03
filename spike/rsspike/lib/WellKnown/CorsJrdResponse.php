<?php

declare(strict_types=1);

namespace OCA\RsSpike\WellKnown;

use OCP\AppFramework\Http\Response;
use OCP\Http\WellKnown\IResponse;
use OCP\Http\WellKnown\JrdResponse;

/** WebFinger must be readable cross-origin (RFC 7033 §5). */
class CorsJrdResponse implements IResponse {
	public function __construct(private JrdResponse $jrd) {
	}

	public function toHttpResponse(): Response {
		$response = $this->jrd->toHttpResponse();
		$response->addHeader('Access-Control-Allow-Origin', '*');
		return $response;
	}
}
