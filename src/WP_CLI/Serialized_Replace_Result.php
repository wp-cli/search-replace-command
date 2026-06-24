<?php

namespace WP_CLI;

/**
 * Simple value object returned by FileSearchReplacer when processing serialized data.
 */
final class Serialized_Replace_Result {

	/**
	 * Text before the serialized portion.
	 *
	 * @var string
	 */
	public $pre;

	/**
	 * The rebuilt serialized portion (with updated length if needed).
	 *
	 * @var string
	 */
	public $serialized_portion;

	/**
	 * Text after the serialized portion.
	 *
	 * @var string
	 */
	public $post;

	/**
	 * @param string $pre                Text before the serialized portion.
	 * @param string $serialized_portion The rebuilt serialized portion.
	 * @param string $post               Text after the serialized portion.
	 */
	public function __construct( $pre, $serialized_portion, $post ) {
		$this->pre                = $pre;
		$this->serialized_portion = $serialized_portion;
		$this->post               = $post;
	}
}
