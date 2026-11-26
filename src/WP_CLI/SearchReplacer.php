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
	 * Whether renaming the keys or property names of an object failed
	 * during the current run().
	 *
	 * @var bool
	 */
	private $key_failure = false;

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
	 * With key recursion enabled, the replacement is all or nothing: if
	 * renaming the keys or property names of any object in $data fails, the
	 * original $data is returned and no log entries are kept for it. For a
	 * serialized string (which is all the command passes) that means the value
	 * is left unchanged. For an array holding live objects, those objects may
	 * still have been partly modified in place.
	 *
	 * @param array|string $data            The data to operate on.
	 * @param bool         $serialised      Does the value of $data need to be unserialized?
	 *
	 * @return array       The original array with all elements replaced as needed.
	 */
	public function run( $data, $serialised = false ) {
		if ( ! $this->recurse_keys ) {
			return $this->run_recursively( $data, $serialised );
		}

		$log_position      = count( $this->log_data );
		$this->key_failure = false;
		try {
			return $this->run_recursively( $data, $serialised );
		} catch ( Exception $exception ) {
			if ( ! $this->key_failure ) {
				throw $exception;
			}
			$this->key_failure = false;
			array_splice( $this->log_data, $log_position );
			return $data;
		}
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
		} catch ( Exception $exception ) {
			// A failed key or property name replacement discards the whole
			// value, so pass it on up to run().
			if ( $this->key_failure ) {
				throw $exception;
			}
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
	 * Replace occurrences of the search string within an array key or property name.
	 *
	 * Integer keys are returned unchanged. If the replacement fails (for
	 * example a PCRE error in regex mode), the original key is kept instead of
	 * turning it into an empty string.
	 *
	 * @param int|string $key The key or property name.
	 * @return int|string The replaced key, or the original key.
	 */
	private function replace_key( $key ) {
		if ( ! is_string( $key ) ) {
			return $key;
		}
		$new_key = $this->replace_string( $key );
		return is_string( $new_key ) ? $new_key : $key;
	}

	/**
	 * Work out the replacement for each key of a container.
	 *
	 * Log entries produced while replacing the keys are kept apart from the
	 * value log, so that they can be committed only once the container
	 * accepts the renames (see commit_key_logs()).
	 *
	 * @param array<int|string> $keys The keys or property names.
	 * @return array{0: array<int|string, int|string>, 1: array<int|string, string[]>} Map of original key to
	 *                                destination key, and the pending log entries for each key.
	 */
	private function plan_key_renames( $keys ) {
		$renames  = array();
		$key_logs = array();
		foreach ( $keys as $key ) {
			$mark            = count( $this->log_data );
			$renames[ $key ] = $this->replace_key( $key );
			// Move only the entries appended for this key out of the value log,
			// instead of rebuilding the whole log for every key.
			$pending  = array();
			$appended = count( $this->log_data ) - $mark;
			for ( $i = 0; $i < $appended; $i++ ) {
				$pending[] = array_pop( $this->log_data );
			}
			$key_logs[ $key ] = array_reverse( $pending );
		}
		return array( $renames, $key_logs );
	}

	/**
	 * Add the log entries of the keys that were actually renamed.
	 *
	 * @param array<int|string, int|string> $renames  Map of original key to destination key.
	 * @param array<int|string, string[]>   $key_logs Pending log entries for each key.
	 * @param int                           $position Position in the log at which to insert the entries.
	 * @return void
	 */
	private function commit_key_logs( $renames, $key_logs, $position ) {
		$accepted = array();
		foreach ( $renames as $key => $new_key ) {
			if ( $new_key !== $key ) {
				foreach ( $key_logs[ $key ] as $entry ) {
					$accepted[] = $entry;
				}
			}
		}
		if ( $accepted ) {
			array_splice( $this->log_data, $position, 0, $accepted );
		}
	}

	/**
	 * Recurse into an array, replacing string keys as well as values.
	 *
	 * Renamed keys keep their original position. Shared references between
	 * elements are preserved by iterating by reference. When two keys would
	 * map onto the same key, the keys are left unchanged (values are still
	 * replaced) and a warning is emitted instead of silently discarding a value.
	 *
	 * @param array $data            The array to process.
	 * @param int   $recursion_level Current recursion depth.
	 * @param array $visited_data    Previously seen arrays and objects.
	 * @return array The processed array.
	 */
	private function replace_array_keys( $data, $recursion_level, $visited_data ) {
		list( $renames, $key_logs ) = $this->plan_key_renames( array_keys( $data ) );
		if ( $this->has_destination_collision( $renames, false ) ) {
			\WP_CLI::warning( 'Skipping key replacement for an array: two keys would map onto the same key and a value would be lost.' );
			$renames = array_combine( array_keys( $renames ), array_keys( $renames ) );
		}
		$log_position = count( $this->log_data );
		$replaced     = array();
		foreach ( $data as $key => &$value ) {
			$value                        = $this->run_recursively( $value, false, $recursion_level + 1, $visited_data );
			$replaced[ $renames[ $key ] ] =& $value;
		}
		unset( $value );
		$this->commit_key_logs( $renames, $key_logs, $log_position );
		return $replaced;
	}

	/**
	 * Recurse into an object, replacing string property names as well as values.
	 *
	 * All values are read and processed before the object is modified, so a
	 * renamed property can never overwrite a source property that has not
	 * been read yet. When two property names would map onto the same name,
	 * the property names are left unchanged (values are still replaced) and a
	 * warning is emitted instead of silently discarding a value.
	 *
	 * Readonly properties (PHP 8.1+) are never renamed, and no property is
	 * renamed onto a readonly property. Properties that share a PHP reference
	 * keep sharing it after a rename. If modifying the object fails, the
	 * object is not restored: the whole value that run() is processing is
	 * left unchanged instead (see fail_key_replacement()).
	 *
	 * ArrayAccess implementations may normalize offsets on write. Offsets are
	 * only renamed for implementations whose offset semantics are known
	 * (ArrayObject, ArrayIterator and the Requests case-insensitive
	 * dictionary); for any other ArrayAccess implementation the original
	 * offsets are kept.
	 *
	 * @param object $data            The object to process.
	 * @param bool   $is_array_access Whether the object implements ArrayAccess.
	 * @param int    $recursion_level Current recursion depth.
	 * @param array  $visited_data    Previously seen arrays and objects.
	 * @return object The processed object.
	 */
	private function replace_object_property_names( $data, $is_array_access, $recursion_level, $visited_data ) {
		$keys = array();
		foreach ( $data as $key => $value ) {
			$keys[] = $key;
		}
		list( $renames, $key_logs ) = $this->plan_key_renames( $keys );

		if ( ! $is_array_access ) {
			// Property names are always strings, but as keys of $renames numeric
			// names such as "8" become integers. Compare them as strings, so that
			// an unchanged numeric property name is not treated as renamed.
			foreach ( $renames as $key => $new_key ) {
				if ( (string) $new_key === (string) $key ) {
					$renames[ $key ] = $key;
				}
			}
		}

		$case_insensitive = false;
		$keep_offsets     = false;
		if ( $is_array_access ) {
			if ( $data instanceof \WpOrg\Requests\Utility\CaseInsensitiveDictionary || is_a( $data, 'Requests_Utility_CaseInsensitiveDictionary' ) ) {
				$case_insensitive = true;
			} elseif ( ! $data instanceof \ArrayObject && ! $data instanceof \ArrayIterator ) {
				$keep_offsets = true;
			}
		}

		$readonly = $is_array_access ? array() : $this->get_readonly_property_names( $data );
		foreach ( $renames as $key => $new_key ) {
			if ( $new_key !== $key && ( isset( $readonly[ $key ] ) || isset( $readonly[ $new_key ] ) ) ) {
				\WP_CLI::warning(
					sprintf(
						'Skipping key replacement for property "%s" of an object of class "%s": a readonly property cannot be renamed or overwritten.',
						$key,
						get_class( $data )
					)
				);
				$renames[ $key ] = $key;
			}
		}

		$renamed = false;
		foreach ( $renames as $key => $new_key ) {
			if ( $new_key !== $key ) {
				$renamed = true;
				break;
			}
		}

		if ( $renamed && $keep_offsets ) {
			\WP_CLI::warning(
				sprintf(
					'Skipping key replacement for an object of class "%s": its offset semantics are unknown.',
					get_class( $data )
				)
			);
			$renames = array_combine( array_keys( $renames ), array_keys( $renames ) );
		} elseif ( $renamed && $this->has_destination_collision( $renames, $case_insensitive ) ) {
			\WP_CLI::warning( 'Skipping key replacement for an object: two property names would map onto the same name and a value would be lost.' );
			$renames = array_combine( array_keys( $renames ), array_keys( $renames ) );
		}

		try {
			// Take a reference to each property that is renamed, so that it keeps
			// any reference it shares with other properties. Properties that keep
			// their name are read and assigned normally, so that, for example,
			// PHP 8.4 `set` hooks still apply to them.
			$refs      = array();
			$originals = array();
			foreach ( $renames as $key => $new_key ) {
				if ( ! $is_array_access && $new_key !== $key ) {
					$refs[ $key ]      = &$data->$key;
					$originals[ $key ] = $refs[ $key ];
				} else {
					$originals[ $key ] = $this->read_property( $data, $is_array_access, $key );
				}
			}

			// Stage all processed values before touching the object.
			$log_position = count( $this->log_data );
			$values       = array();
			foreach ( $renames as $key => $new_key ) {
				$values[ $key ] = $this->run_recursively( $originals[ $key ], false, $recursion_level + 1, $visited_data );
				if ( isset( $readonly[ $key ] ) && $values[ $key ] !== $originals[ $key ] ) {
					throw new \Error( sprintf( 'Cannot modify readonly property %s::$%s', get_class( $data ), $key ) ); // phpcs:ignore PHPCompatibility.Classes.NewClasses.errorFound
				}
			}

			foreach ( $renames as $key => $new_key ) {
				if ( $new_key !== $key ) {
					$this->remove_property( $data, $is_array_access, $key );
				}
			}
			foreach ( $renames as $key => $new_key ) {
				if ( isset( $readonly[ $key ] ) ) {
					continue;
				}
				if ( $is_array_access ) {
					$this->write_property( $data, true, $new_key, $values[ $key ] );
				} elseif ( $new_key !== $key ) {
					$data->$new_key = &$refs[ $key ];
					$refs[ $key ]   = $values[ $key ];
				} else {
					$data->$key = $values[ $key ];
				}
			}
		} catch ( \Error $exception ) { // phpcs:ignore PHPCompatibility.Classes.NewClasses.errorFound
			$this->fail_key_replacement( $data, $exception );
		} catch ( Exception $exception ) {
			// ArrayAccess implementations may throw any exception, for example
			// from offsetUnset().
			$this->fail_key_replacement( $data, $exception );
		}

		$this->commit_key_logs( $renames, $key_logs, $log_position );
		return $data;
	}

	/**
	 * Abandon the current run() after renaming the keys or property names of an object failed.
	 *
	 * The object may be left partly modified, so the whole value that is
	 * being processed is discarded: run() returns it unchanged instead.
	 *
	 * @param object               $data      The object that failed to be modified.
	 * @param \Throwable|Exception $exception The error or exception thrown.
	 * @return never
	 *
	 * @throws Exception Always, to unwind to run().
	 */
	private function fail_key_replacement( $data, $exception ) {
		if ( $this->key_failure ) {
			// Already reported by a nested object.
			throw $exception;
		}
		$this->key_failure = true;
		\WP_CLI::warning(
			sprintf(
				'Skipping an inconvertible serialized object of type "%s": the whole value was left unchanged, so replacements might not be complete. Reason: %s.',
				get_class( $data ),
				$exception->getMessage()
			)
		);
		throw new Exception( $exception->getMessage(), (int) $exception->getCode(), $exception );
	}

	/**
	 * Get the names of the readonly properties of an object.
	 *
	 * Readonly properties exist as of PHP 8.1; on older versions there are none.
	 *
	 * @param object $data The object to inspect.
	 * @return array<string, bool> Readonly property names as keys.
	 */
	private function get_readonly_property_names( $data ) {
		$names = array();
		foreach ( ( new \ReflectionObject( $data ) )->getProperties() as $property ) {
			if ( method_exists( $property, 'isReadOnly' ) && $property->isReadOnly() ) {
				$names[ $property->getName() ] = true;
			}
		}
		return $names;
	}

	/**
	 * Check whether two renamed keys would end up as the same stored key.
	 *
	 * Destination keys are compared by how PHP actually stores them as array
	 * keys (so `8` and `'08'` stay distinct, while `'8'` and `8` collide), and
	 * optionally case-insensitively for containers that normalize offsets.
	 *
	 * @param array $renames          Map of original key to destination key.
	 * @param bool  $case_insensitive Whether destination keys are compared case-insensitively.
	 * @return bool Whether at least two destination keys collide.
	 */
	private function has_destination_collision( $renames, $case_insensitive ) {
		$seen = array();
		foreach ( $renames as $new_key ) {
			if ( $case_insensitive && is_string( $new_key ) ) {
				$new_key = strtolower( $new_key );
			}
			if ( isset( $seen[ $new_key ] ) ) {
				return true;
			}
			$seen[ $new_key ] = true;
		}
		return false;
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
