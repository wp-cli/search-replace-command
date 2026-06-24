<?php
/**
 * Search and replace within a SQL file using the go-search-replace algorithm.
 */
class Search_Replace_File_Command extends WP_CLI_Command {

	/**
	 * Search and replace within a SQL file.
	 *
	 * This command uses the same algorithm as Automattic's go-search-replace utility.
	 * It operates directly on SQL text (including serialized PHP strings) and correctly
	 * updates serialized string length markers. This makes it especially useful for
	 * processing database dumps without needing a live database connection.
	 *
	 * ## OPTIONS
	 *
	 * [<old>]
	 * : A string to search for within the SQL file.
	 *
	 * [<new>]
	 * : Replace instances of the first string with this new string.
	 *
	 * [<input-file>]
	 * : Path to the input SQL file. Use '-' to read from STDIN. If omitted, defaults to STDIN.
	 *
	 * [<output-file>]
	 * : Path to write the transformed SQL. Use '-' to write to STDOUT. If omitted and --in-place is not used, defaults to STDOUT.
	 *
	 * [--old=<value>]
	 * : An alternative way to specify the search string. Use this when the search string starts with '--'.
	 *
	 * [--new=<value>]
	 * : An alternative way to specify the replacement string. Use this when the replacement string starts with '--'.
	 *
	 * [--in-place]
	 * : Edit the input file in place. Cannot be used together with an explicit output file.
	 *
	 * [--dry-run]
	 * : Run the replacement and show what would change, but do not write any output.
	 *
	 * [--verbose]
	 * : Show additional information during processing.
	 *
	 * ## EXAMPLES
	 *
	 *     # Basic usage with files
	 *     $ wp search-replace file example.com newdomain.com dump.sql updated.sql
	 *
	 *     # Read from STDIN and write to STDOUT
	 *     $ cat dump.sql | wp search-replace file example.com newdomain.com - -
	 *
	 *     # In-place edit
	 *     $ wp search-replace file example.com newdomain.com dump.sql --in-place
	 *
	 *     # Using --old and --new flags
	 *     $ wp search-replace file --old='--old-value' --new='--new-value' dump.sql
	 *
	 * @param array<string> $args Positional arguments.
	 * @param array{'old'?: string, 'new'?: string, 'in-place'?: bool, 'dry-run'?: bool, 'verbose'?: bool} $assoc_args Associative arguments.
	 */
	public function __invoke( $args, $assoc_args ) {
		// Support --old and --new flags as an alternative to positional arguments.
		$old_flag = \WP_CLI\Utils\get_flag_value( $assoc_args, 'old' );
		$new_flag = \WP_CLI\Utils\get_flag_value( $assoc_args, 'new' );

		$both_flags_provided = null !== $old_flag && null !== $new_flag;
		$has_positional_args = ! empty( $args );

		if ( $both_flags_provided && $has_positional_args ) {
			\WP_CLI::error( 'Cannot use both positional arguments and --old/--new flags. Please use one method or the other.' );
		}

		$old = null !== $old_flag ? $old_flag : array_shift( $args );
		$new = null !== $new_flag ? $new_flag : array_shift( $args );

		if ( null === $old || null === $new || '' === $old ) {
			$missing = [];
			if ( null === $old || '' === $old ) {
				$missing[] = '<old>';
			}
			if ( null === $new ) {
				$missing[] = '<new>';
			}
			$error_msg = count( $missing ) === 2
				? 'Please provide both <old> and <new> arguments.'
				: sprintf( 'Please provide the %s argument.', $missing[0] );

			$error_msg .= "\n\nNote: If your search or replacement string starts with '--', use the flag syntax instead:"
				. "\n  wp search-replace file --old='--text' --new='replacement' input.sql output.sql";

			\WP_CLI::error( $error_msg );
		}

		$in_place = \WP_CLI\Utils\get_flag_value( $assoc_args, 'in-place', false );
		$dry_run  = \WP_CLI\Utils\get_flag_value( $assoc_args, 'dry-run', false );
		$verbose  = \WP_CLI\Utils\get_flag_value( $assoc_args, 'verbose', false );

		$input_file  = array_shift( $args );
		$output_file = array_shift( $args );

		if ( null === $input_file ) {
			$input_file = '-';
		}

		if ( null === $output_file ) {
			$output_file = $in_place ? $input_file : '-';
		}

		if ( $in_place && $input_file !== $output_file ) {
			\WP_CLI::error( 'Cannot specify an output file when using --in-place.' );
		}

		if ( '-' === $input_file && $in_place ) {
			\WP_CLI::error( 'Cannot use --in-place when reading from STDIN.' );
		}

		$replacer = new \WP_CLI\FileSearchReplacer();

		$replacements = [
			[
				'from' => $old,
				'to'   => $new,
			],
		];

		if ( $dry_run ) {
			$this->do_dry_run( $replacer, $input_file, $replacements, $verbose );
			return;
		}

		$this->do_replace( $replacer, $input_file, $output_file, $replacements, $verbose );
	}

	/**
	 * Perform a dry-run (read input, process, but do not write).
	 *
	 * @param array<int, array{from:string,to:string}> $replacements
	 */
	private function do_dry_run( \WP_CLI\FileSearchReplacer $replacer, string $input_file, array $replacements, bool $verbose ): void {
		$input_handle = $this->open_input( $input_file );

		$total_lines        = 0;
		$changed_lines      = 0;
		$total_replacements = 0;

		while ( true ) {
			$line = fgets( $input_handle );
			if ( false === $line ) {
				break;
			}
			++$total_lines;
			$processed = $replacer->process_line( $line, $replacements );

			if ( $processed !== $line ) {
				++$changed_lines;
				// Count how many times old appears in the original line
				$old                 = $replacements[0]['from'];
				$total_replacements += substr_count( $line, $old );
			}

			if ( $verbose ) {
				\WP_CLI::line( sprintf( 'Line %d: %s', $total_lines, $processed !== $line ? 'changed' : 'unchanged' ) );
			}
		}

		if ( '-' !== $input_file ) {
			fclose( $input_handle );
		}

		\WP_CLI::success(
			sprintf(
				'Dry run complete. %d lines processed, %d lines would change, %d total replacements.',
				$total_lines,
				$changed_lines,
				$total_replacements
			)
		);
	}

	/**
	 * Perform the actual replacement and write output.
	 *
	 * @param array<int, array{from:string,to:string}> $replacements
	 */
	private function do_replace( \WP_CLI\FileSearchReplacer $replacer, string $input_file, string $output_file, array $replacements, bool $verbose ): void {
		$input_handle  = $this->open_input( $input_file );
		$output_handle = $this->open_output( $output_file );

		$total_lines        = 0;
		$changed_lines      = 0;
		$total_replacements = 0;

		while ( true ) {
			$line = fgets( $input_handle );
			if ( false === $line ) {
				break;
			}
			++$total_lines;
			$processed = $replacer->process_line( $line, $replacements );

			fwrite( $output_handle, $processed );

			if ( $processed !== $line ) {
				++$changed_lines;
				$old                 = $replacements[0]['from'];
				$total_replacements += substr_count( $line, $old );
			}

			if ( $verbose ) {
				\WP_CLI::line( sprintf( 'Line %d: %s', $total_lines, $processed !== $line ? 'changed' : 'unchanged' ) );
			}
		}

		if ( '-' !== $input_file ) {
			fclose( $input_handle );
		}
		if ( '-' !== $output_file ) {
			fclose( $output_handle );
		}

		$success_msg = 1 === $total_replacements
			? 'Made 1 replacement.'
			: sprintf( 'Made %d replacements.', $total_replacements );

		\WP_CLI::success( $success_msg );
	}

	/**
	 * Open an input handle (file or STDIN).
	 *
	 * @return resource
	 */
	private function open_input( string $input_file ) {
		if ( '-' === $input_file ) {
			$handle = fopen( 'php://stdin', 'rb' );
			if ( false === $handle ) {
				\WP_CLI::error( 'Unable to open STDIN for reading.' );
			}
			return $handle;
		}

		$handle = @fopen( $input_file, 'rb' );
		if ( false === $handle ) {
			$error = error_get_last();
			\WP_CLI::error( sprintf( 'Unable to open input file "%s" for reading: %s.', $input_file, $error['message'] ?? 'unknown error' ) );
		}
		return $handle;
	}

	/**
	 * Open an output handle (file or STDOUT).
	 *
	 * @return resource
	 */
	private function open_output( string $output_file ) {
		if ( '-' === $output_file ) {
			$handle = fopen( 'php://stdout', 'wb' );
			if ( false === $handle ) {
				\WP_CLI::error( 'Unable to open STDOUT for writing.' );
			}
			return $handle;
		}

		$handle = @fopen( $output_file, 'wb' );
		if ( false === $handle ) {
			$error = error_get_last();
			\WP_CLI::error( sprintf( 'Unable to open output file "%s" for writing: %s.', $output_file, $error['message'] ?? 'unknown error' ) );
		}
		return $handle;
	}
}
