<?php

namespace WP_CLI;

use ArrayObject;
use Exception;

class SearchReplacer {

	/**
	 * @var string
	 */
	private $from;

	/**
	 * @var string
	 */
	private $to;

	/**
	 * @var string
	 */
	private $from_json;

	/**
	 * @var string
	 */
	private $to_json;

	/**
	 * @var bool
	 */
	private $recurse_objects;

	/**
	 * @var bool
	 */
	private $recurse_keys;

	/**
	 * @var bool
	 */
	private $regex;

	/**
	 * @var string
	 */
	private $regex_flags;

	/**
	 * @var string
	 */
	private $regex_delimiter;

	/**
	 * @var int
	 */
	private $regex_limit;

	/**
	 * @var bool
	 */
	private $logging;

	/**
	 * @var string[]
	 */
	private $log_data = [];

	/**
	 * @var int
	 */
	private $max_recursion;

	/**
	 * @var array<string, mixed>
	 */
	private $unserialize_options;

	/**
	 * @param string  $from            String we're looking to replace.
	 * @param string  $to              What we want it to be replaced with.
	 * @param bool    $recurse_objects Should objects be recursively replaced?
	 * @param bool    $regex           Whether `$from` is a regular expression.
	 * @param string  $regex_flags     Flags for regular expression.
	 * @param string  $regex_delimiter Delimiter for regular expression.
	 * @param bool    $logging         Whether logging.
	 * @param integer $regex_limit     The maximum possible replacements for each pattern in each subject string.
	 * @param bool    $recurse_keys    Should array keys and object property names be recursively replaced?
	 */
	public function __construct( $from, $to, $recurse_objects = false, $regex = false, $regex_flags = '', $regex_delimiter = '/', $logging = false, $regex_limit = -1, $recurse_keys = false ) {
		$this->from            = $from;
		$this->to              = $to;
		$this->recurse_objects = $recurse_objects;
		$this->recurse_keys    = $recurse_keys;
		$this->regex           = $regex;
		$this->regex_flags     = $regex_flags;
		$this->regex_delimiter = $regex_delimiter;
		$this->regex_limit     = $regex_limit;
		$this->logging         = $logging;
		$this->clear_log_data();

		// Compute JSON-encoded versions (stripping outer quotes) for handling raw JSON values in the database.
		$this->from_json = \Search_Replace_Command::json_encode_strip_quotes( $from );
		$this->to_json   = \Search_Replace_Command::json_encode_strip_quotes( $to );

		// Get the XDebug nesting level. Will be zero (no limit) if no value is set
		$this->max_recursion = intval( ini_get( 'xdebug.max_nesting_level' ) );

		/**
		 * Filter the options passed to unserialize() during search-replace.
		 *
		 * Defaults to `[ 'allowed_classes' => [ 'stdClass' ] ]` to allow the
		 * built-in stdClass (used extensively by WordPress, e.g. theme mods)
		 * while blocking arbitrary user-defined class instantiation. Use this
		 * hook to allow additional classes when needed.
		 *
		 * @param array<string, mixed> $options Options array for unserialize().
		 */
		$this->unserialize_options = \WP_CLI::do_hook( 'search_replace_unserialize_options', [ 'allowed_classes' => [ 'stdClass' ] ] );
	}

	/**
	 * Take a serialised array and unserialise it replacing elements as needed and
	 * unserialising any subordinate arrays and performing the replace on those too.
	 * Ignores any serialized objects unless $recurse_objects is set to true.
	 *
	 * @param array|string $data            The data to operate on.
	 * @param bool         $serialised      Does the value of $data need to be unserialized?
	 *
	 * @return array       The original array with all elements replaced as needed.
	 */
	public function run( $data, $serialised = false ) {
		return $this->run_recursively( $data, $serialised );
	}

	/**
	 * @param int          $recursion_level Current recursion depth within the original data.
	 * @param array        $visited_data    Data that has been seen in previous recursion iterations.
	 */
	private function run_recursively( $data, $serialised, $recursion_level = 0, $visited_data = array() ) {

		// some unseriliased data cannot be re-serialised eg. SimpleXMLElements
		try {

			if ( $this->recurse_objects ) {

				// If we've reached the maximum recursion level, short circuit
				if ( 0 !== $this->max_recursion && $recursion_level >= $this->max_recursion ) {
					return $data;
				}

				if ( is_array( $data ) || is_object( $data ) ) {
					// If we've seen this exact object or array before, short circuit
					if ( in_array( $data, $visited_data, true ) ) {
						return $data; // Avoid infinite loops when there's a cycle
					}
					// Add this data to the list of
					$visited_data[] = $data;
				}
			}

			try {
				// The error suppression operator is not enough in some cases, so we disable
				// reporting of notices and warnings as well.
				$error_reporting = error_reporting();
				error_reporting( $error_reporting & ~E_NOTICE & ~E_WARNING );
				$unserialized = is_string( $data ) ? @unserialize( $data, $this->unserialize_options ) : false;
				error_reporting( $error_reporting );

			} catch ( \TypeError $exception ) { // phpcs:ignore PHPCompatibility.Classes.NewClasses.typeerrorFound
				// This type error is thrown when trying to unserialize a string that does not fit the
				// type declarations of the properties it is supposed to fill.
				// This type checking was introduced with PHP 8.1.
				// See https://github.com/wp-cli/search-replace-command/issues/191
				\WP_CLI::warning(
					sprintf(
						'Skipping an inconvertible serialized object: "%s", replacements might not be complete. Reason: %s.',
						$data,
						$exception->getMessage()
					)
				);

				throw new Exception( $exception->getMessage(), $exception->getCode(), $exception );
			}

			if ( false !== $unserialized ) {
				$data = $this->run_recursively( $unserialized, true, $recursion_level + 1 );
			} elseif ( is_array( $data ) ) {
				if ( $this->recurse_keys ) {
					$data = $this->replace_array_keys( $data, $recursion_level, $visited_data );
				} else {
					$keys = array_keys( $data );
					foreach ( $keys as $key ) {
						$data[ $key ] = $this->run_recursively( $data[ $key ], false, $recursion_level + 1, $visited_data );
					}
				}
			} elseif ( $this->recurse_objects && ( is_object( $data ) || $data instanceof \__PHP_Incomplete_Class ) ) {
				if ( $data instanceof \__PHP_Incomplete_Class ) {
					$array = new ArrayObject( $data );
					\WP_CLI::warning(
						sprintf(
							'Skipping an uninitialized class "%s", replacements might not be complete.',
							$array['__PHP_Incomplete_Class_Name']
						)
					);
				} else {
					try {
						$is_array_access = $data instanceof \ArrayAccess;
						if ( $this->recurse_keys ) {
							$data = $this->replace_object_property_names( $data, $is_array_access, $recursion_level, $visited_data );
						} else {
							foreach ( $data as $key => $value ) {
								$value = $this->run_recursively( $value, false, $recursion_level + 1, $visited_data );
								if ( $is_array_access ) {
									$data[ $key ] = $value;
								} else {
									$data->$key = $value;
								}
							}
						}
					} catch ( \Error $exception ) { // phpcs:ignore PHPCompatibility.Classes.NewClasses.errorFound
						// This error is thrown when the object that was unserialized cannot be iterated upon.
						// The most notable reason is an empty `mysqli_result` object which is then considered to be "already closed".
						// See https://github.com/wp-cli/search-replace-command/pull/192#discussion_r1412310179
						\WP_CLI::warning(
							sprintf(
								'Skipping an inconvertible serialized object of type "%s", replacements might not be complete. Reason: %s.',
								is_object( $data ) ? get_class( $data ) : gettype( $data ),
								$exception->getMessage()
							)
						);

						throw new Exception( $exception->getMessage(), $exception->getCode(), $exception );
					}
				}
			} elseif ( is_string( $data ) ) {
				$data = $this->replace_string( $data );
			}

			if ( $serialised ) {
				return serialize( $data );
			}
		} catch ( Exception $exception ) { // phpcs:ignore Generic.CodeAnalysis.EmptyStatement.DetectedCatch -- Intentionally empty.

		}

		return $data;
	}

	/**
	 * Replace occurrences of the search string within a single string.
	 *
	 * Used for values as well as array keys and object property names when
	 * key recursion is enabled.
	 *
	 * @param string $data The string to operate on.
	 * @return string The string with all replacements made as needed.
	 */
	private function replace_string( $data ) {
		if ( $this->logging ) {
			$old_data = $data;
		}
		if ( $this->regex ) {
			$search_regex  = $this->regex_delimiter;
			$search_regex .= $this->from;
			$search_regex .= $this->regex_delimiter;
			$search_regex .= $this->regex_flags;

			$result = preg_replace( $search_regex, $this->to, $data, $this->regex_limit );
			if ( null === $result || PREG_NO_ERROR !== preg_last_error() ) {
				\WP_CLI::warning(
					sprintf(
						'The provided regular expression threw a PCRE error - %s',
						$this->preg_error_message( $result )
					)
				);
			}
			$data = $result;
		} else {
			$data = str_replace( $this->from, $this->to, $data );
			if ( $this->from_json !== $this->from ) {
				$data = str_replace( $this->from_json, $this->to_json, $data );
			}
		}
		if ( $this->logging && $old_data !== $data ) {
			$this->log_data[] = $old_data;
		}

		return $data;
	}

	/**
	 * Recurse into an array, replacing string keys as well as values.
	 *
	 * Renamed keys keep their original position. Shared references between
	 * elements are preserved by iterating by reference. When two keys would
	 * map onto the same key, the array is left unchanged and a warning is
	 * emitted instead of silently discarding a value.
	 *
	 * @param array $data            The array to process.
	 * @param int   $recursion_level Current recursion depth.
	 * @param array $visited_data    Previously seen arrays and objects.
	 * @return array The processed array.
	 */
	private function replace_array_keys( $data, $recursion_level, $visited_data ) {
		$renames = array();
		foreach ( array_keys( $data ) as $key ) {
			$renames[ $key ] = is_string( $key ) ? $this->replace_string( $key ) : $key;
		}
		if ( count( array_unique( $renames, SORT_REGULAR ) ) !== count( $renames ) ) {
			\WP_CLI::warning( 'Skipping key replacement for an array: two keys would map onto the same key and a value would be lost.' );
			return $data;
		}
		$replaced = array();
		foreach ( $data as $key => &$value ) {
			$value                        = $this->run_recursively( $value, false, $recursion_level + 1, $visited_data );
			$replaced[ $renames[ $key ] ] =& $value;
		}
		unset( $value );
		return $replaced;
	}

	/**
	 * Recurse into an object, replacing string property names as well as values.
	 *
	 * When two property names would map onto the same name, the object is
	 * left unchanged and a warning is emitted instead of silently
	 * discarding a value.
	 *
	 * @param object $data            The object to process.
	 * @param bool   $is_array_access Whether the object implements ArrayAccess.
	 * @param int    $recursion_level Current recursion depth.
	 * @param array  $visited_data    Previously seen arrays and objects.
	 * @return object The processed object.
	 */
	private function replace_object_property_names( $data, $is_array_access, $recursion_level, $visited_data ) {
		$renames = array();
		foreach ( $data as $key => $value ) {
			$renames[ $key ] = is_string( $key ) ? $this->replace_string( $key ) : $key;
		}
		if ( count( array_unique( $renames, SORT_REGULAR ) ) !== count( $renames ) ) {
			\WP_CLI::warning( 'Skipping key replacement for an object: two property names would map onto the same name and a value would be lost.' );
			return $data;
		}
		foreach ( $renames as $key => $new_key ) {
			$value = $this->run_recursively( $this->read_property( $data, $is_array_access, $key ), false, $recursion_level + 1, $visited_data );
			if ( $new_key !== $key ) {
				$this->remove_property( $data, $is_array_access, $key );
			}
			$this->write_property( $data, $is_array_access, $new_key, $value );
		}
		return $data;
	}

	/**
	 * Read one property or offset from an object or ArrayAccess instance.
	 *
	 * @param object $data            The object to read from.
	 * @param bool   $is_array_access Whether the object implements ArrayAccess.
	 * @param string $key             The property name or offset.
	 * @return mixed The property value.
	 */
	private function read_property( $data, $is_array_access, $key ) {
		return $is_array_access ? $data[ $key ] : $data->$key;
	}

	/**
	 * Remove one property or offset from an object or ArrayAccess instance.
	 *
	 * @param object $data            The object to modify, by reference.
	 * @param bool   $is_array_access Whether the object implements ArrayAccess.
	 * @param string $key             The property name or offset.
	 * @return void
	 */
	private function remove_property( &$data, $is_array_access, $key ) {
		if ( $is_array_access ) {
			unset( $data[ $key ] );
		} else {
			unset( $data->$key );
		}
	}

	/**
	 * Write one property or offset on an object or ArrayAccess instance.
	 *
	 * @param object $data            The object to modify, by reference.
	 * @param bool   $is_array_access Whether the object implements ArrayAccess.
	 * @param string $key             The property name or offset.
	 * @param mixed  $value           The value to write.
	 * @return void
	 */
	private function write_property( &$data, $is_array_access, $key, $value ) {
		if ( $is_array_access ) {
			$data[ $key ] = $value;
		} else {
			$data->$key = $value;
		}
	}

	/**
	 * Gets existing data saved for this run when logging.
	 * @return string[] Array of data strings, prior to replacements.
	 */
	public function get_log_data() {
		return $this->log_data;
	}

	/**
	 * Clears data stored for logging.
	 */
	public function clear_log_data() {
		$this->log_data = array();
	}

	/**
	 * Get the PCRE error constant name from an error value.
	 *
	 * @param  integer $error Error code.
	 * @return string         Error constant name.
	 */
	private function preg_error_message( $error ) {
		static $error_names = null;

		if ( null === $error_names ) {
			$definitions    = get_defined_constants( true );
			$pcre_constants = array_key_exists( 'pcre', $definitions )
				? $definitions['pcre']
				: array();
			$error_names    = array_flip( $pcre_constants );
		}

		return isset( $error_names[ $error ] )
			? $error_names[ $error ]
			: '<unknown error>';
	}
}
