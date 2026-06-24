<?php

namespace WP_CLI;

/**
 * Port of Automattic's go-search-replace serialized string fixer.
 * Works directly on SQL dump text without requiring a live database.
 */
class FileSearchReplacer {

	/**
	 * Run replacements against a SQL file and write the result to another file.
	 *
	 * @param string $input_path  Path to the input SQL file.
	 * @param string $output_path Path to the output SQL file.
	 * @param array  $replacements Array of replacement pairs.
	 */
	public function replace_in_file( $input_path, $output_path, $replacements ) {
		$normalized = $this->normalize_replacements( $replacements );
		if ( empty( $normalized ) ) {
			if ( $input_path === $output_path ) {
				return;
			}
			if ( ! copy( $input_path, $output_path ) ) {
				throw new \RuntimeException( sprintf( 'Unable to copy "%s" to "%s".', $input_path, $output_path ) );
			}
			return;
		}

		$input = @fopen( $input_path, 'rb' );
		if ( false === $input ) {
			throw new \RuntimeException( sprintf( 'Unable to open "%s" for reading.', $input_path ) );
		}

		$output = @fopen( $output_path, 'wb' );
		if ( false === $output ) {
			fclose( $input );
			throw new \RuntimeException( sprintf( 'Unable to open "%s" for writing.', $output_path ) );
		}

		$line = fgets( $input );
		while ( false !== $line ) {
			fwrite( $output, $this->process_line( $line, $normalized ) );
			$line = fgets( $input );
		}

		$remainder = stream_get_contents( $input );
		if ( false !== $remainder && '' !== $remainder ) {
			fwrite( $output, $this->process_line( $remainder, $normalized ) );
		}

		fclose( $input );
		fclose( $output );
	}

	/**
	 * Replace strings inside a line or chunk of SQL text.
	 *
	 * @param string $line         The line to process.
	 * @param array  $replacements Replacement pairs.
	 * @return string
	 */
	public function process_line( $line, $replacements ) {
		if ( '' === $line ) {
			return '';
		}

		$normalized = $this->normalize_replacements( $replacements );
		if ( empty( $normalized ) ) {
			return $line;
		}

		return $this->fix_line( $line, $normalized );
	}

	/**
	 * Normalize and validate replacement array.
	 *
	 * @param array $replacements Raw replacements.
	 * @return array
	 */
	private function normalize_replacements( $replacements ) {
		$normalized = array();
		foreach ( $replacements as $replacement ) {
			if ( ! is_array( $replacement ) || ! isset( $replacement['from'], $replacement['to'] ) ) {
				throw new \RuntimeException( 'Replacements must be arrays with "from" and "to" keys.' );
			}

			$from = (string) $replacement['from'];
			$to   = (string) $replacement['to'];

			if ( '' === $from ) {
				continue;
			}

			$normalized[] = array(
				'from' => $from,
				'to'   => $to,
			);
		}

		return $normalized;
	}

	/**
	 * Fix a line containing serialized data.
	 *
	 * @param string $line_part    The line chunk.
	 * @param array  $replacements Normalized replacements.
	 * @return string
	 */
	private function fix_line( $line_part, $replacements ) {
		$rebuilt = '';

		while ( '' !== $line_part ) {
			try {
				$result = $this->fix_line_with_serialized_data( $line_part, $replacements );
			} catch ( \Exception $exception ) {
				$rebuilt  .= $line_part;
				break;
			}

			$rebuilt  .= $result->pre . $result->serialized_portion;
			$line_part = $result->post;

			if ( '' === $line_part ) {
				break;
			}
		}

		return $rebuilt;
	}

	/**
	 * Core logic that finds and rebuilds serialized strings.
	 *
	 * @param string $line_part    Line chunk.
	 * @param array  $replacements Replacements.
	 * @return Serialized_Replace_Result
	 */
	private function fix_line_with_serialized_data( $line_part, $replacements ) {
		$prefix = $this->find_serialized_prefix( $line_part );

		if ( null === $prefix ) {
			return new Serialized_Replace_Result(
				$this->replace_by_part( $line_part, $replacements ),
				'',
				''
			);
		}

		$pre = substr( $line_part, 0, $prefix['start'] );
		$pre = $this->replace_by_part( $pre, $replacements );

		$original_byte_size  = (int) $prefix['raw_length'];
		$content_start_index = $prefix['content_start'];

		$current_content_index = $content_start_index;
		$content_byte_count    = 0;
		$content_end_index     = 0;
		$next_slice_index      = null;
		$next_slice_found      = false;
		$max_index             = strlen( $line_part ) - 1;

		while ( $current_content_index < strlen( $line_part ) ) {
			if ( $current_content_index + 2 > $max_index ) {
				throw new \RuntimeException( 'faulty serialized data: out-of-bound index access detected' );
			}

			$char       = $line_part[ $current_content_index ];
			$second_char = $line_part[ $current_content_index + 1 ];
			$third_char  = $line_part[ $current_content_index + 2 ];

			if ( '\\' === $char && $content_byte_count < $original_byte_size ) {
				$unescaped = $this->get_unescaped_bytes_if_escaped( substr( $line_part, $current_content_index, 2 ) );
				$content_byte_count += strlen( $unescaped );
				$current_content_index += 2;
				continue;
			}

			if ( '\\' === $char && '"' === $second_char && ';' === $third_char && $content_byte_count >= $original_byte_size ) {
				$next_slice_index = $current_content_index + 3;
				$content_end_index = $current_content_index - 1;
				$next_slice_found = true;
				break;
			}

			if ( $content_byte_count > $original_byte_size ) {
				throw new \RuntimeException( 'faulty serialized data: calculated byte count does not match given data size' );
			}

			$content_byte_count++;
			$current_content_index++;
		}

		if ( ! $next_slice_found || null === $next_slice_index ) {
			throw new \RuntimeException( 'faulty serialized data: end of serialized data not found' );
		}

		$content = substr( $line_part, $content_start_index, $content_end_index - $content_start_index + 1 );
		$content = $this->replace_by_part( $content, $replacements );
		$content_length = strlen( $this->unescape_content( $content ) );

		$escaped_quote = '\"';
		$rebuilt_serialized_string = 's:' . $content_length . ':' . $escaped_quote . $content . $escaped_quote . ';';

		return new Serialized_Replace_Result(
			$pre,
			$rebuilt_serialized_string,
			substr( $line_part, $next_slice_index )
		);
	}

	/**
	 * Apply replacements to a non-serialized part.
	 *
	 * @param string $part         The part to replace in.
	 * @param array  $replacements Replacements.
	 * @return string
	 */
	private function replace_by_part( $part, $replacements ) {
		foreach ( $replacements as $replacement ) {
			$part = str_replace( $replacement['from'], $replacement['to'], $part );
		}

		return $part;
	}

	/**
	 * Locate a serialized string prefix.
	 *
	 * @param string $line_part Line chunk.
	 * @return array|null
	 */
	private function find_serialized_prefix( $line_part ) {
		$length = strlen( $line_part );

		for ( $index = 0; $index < $length - 4; $index++ ) {
			if ( 's' !== $line_part[ $index ] || ':' !== $line_part[ $index + 1 ] ) {
				continue;
			}

			$digit_start = $index + 2;
			if ( $digit_start >= $length || ! ctype_digit( $line_part[ $digit_start ] ) ) {
				continue;
			}

			$digit_end = $digit_start;
			while ( $digit_end < $length && ctype_digit( $line_part[ $digit_end ] ) ) {
				$digit_end++;
			}

			if ( $digit_end >= $length || ':' !== $line_part[ $digit_end ] ) {
				continue;
			}

			if ( $digit_end + 2 >= $length ) {
				break;
			}

			if ( '\\' !== $line_part[ $digit_end + 1 ] || '"' !== $line_part[ $digit_end + 2 ] ) {
				continue;
			}

			$raw_length = substr( $line_part, $digit_start, $digit_end - $digit_start );

			return array(
				'start'         => $index,
				'raw_length'    => $raw_length,
				'content_start' => $digit_end + 3,
			);
		}

		return null;
	}

	/**
	 * Convert an escaped sequence to its real character.
	 *
	 * @param string $pair Two-character escape sequence.
	 * @return string
	 */
	private function get_unescaped_bytes_if_escaped( $pair ) {
		if ( '' === $pair || '\\' !== $pair[0] ) {
			return $pair;
		}

		$map = array(
			'\\' => '\\',
			"'"  => "'",
			'"'  => '"',
			'n'  => "\n",
			'r'  => "\r",
			't'  => "\t",
			'b'  => "\x08",
			'f'  => "\f",
			'0'  => '0',
		);

		$second = isset( $pair[1] ) ? $pair[1] : '';

		if ( '' !== $second && isset( $map[ $second ] ) ) {
			return $map[ $second ];
		}

		return $pair;
	}

	/**
	 * Unescape an entire content string.
	 *
	 * @param string $escaped Escaped content.
	 * @return string
	 */
	private function unescape_content( $escaped ) {
		$unescaped = '';
		$length    = strlen( $escaped );
		$index     = 0;

		while ( $index < $length ) {
			if ( '\\' === $escaped[ $index ] && $index + 1 < $length ) {
				$pair     = substr( $escaped, $index, 2 );
				$converted = $this->get_unescaped_bytes_if_escaped( $pair );
				if ( 1 === strlen( $converted ) ) {
					$unescaped .= $converted;
					$index     += 2;
					continue;
				}
			}

			$unescaped .= $escaped[ $index ];
			$index++;
		}

		return $unescaped;
	}
}
