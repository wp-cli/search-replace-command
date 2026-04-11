<?php

/**
 * Patches a bug in WP_CLI\Runner::set_alias() where global runtime parameters
 * (url, path, user, etc.) could be injected into $this->assoc_args when both
 * an alias and a matching CLI flag were present simultaneously, causing the
 * subcommand dispatcher to reject them as "unknown" parameters.
 *
 * This patch can be removed once wp-cli/wp-cli ships the fix upstream.
 *
 * @see https://github.com/wp-cli/search-replace-command/issues/225
 */

$file = __DIR__ . '/../vendor/wp-cli/wp-cli/php/WP_CLI/Runner.php';

if ( ! file_exists( $file ) ) {
	return;
}

$contents = file_get_contents( $file );

// Marker that indicates the fix has already been applied.
if ( false !== strpos( $contents, 'fix-runner-set-alias-applied' ) ) {
	return;
}

$old = <<<'PHP'
	private function set_alias( $alias ): void {
		$orig_config = $this->config;
		/** @var array<string, mixed> $alias_config */
		// @phpstan-ignore varTag.type
		$alias_config = (array) $this->aliases[ $alias ];
		$this->config = array_merge( $orig_config, $alias_config );
		foreach ( $alias_config as $key => $_ ) {
			if ( isset( $orig_config[ (string) $key ] ) && ! is_null( $orig_config[ (string) $key ] ) ) {
				// @phpstan-ignore assign.propertyType
				$this->assoc_args[ (string) $key ] = $orig_config[ (string) $key ];
			}
		}
	}
PHP;

$new = <<<'PHP'
	private function set_alias( $alias ): void {
		// fix-runner-set-alias-applied
		$orig_config = $this->config;
		/** @var array<string, mixed> $alias_config */
		// @phpstan-ignore varTag.type
		$alias_config = (array) $this->aliases[ $alias ];
		$this->config = array_merge( $orig_config, $alias_config );
		// Global runtime parameters (url, path, user, etc.) are managed
		// entirely through the config system.  Putting them into $assoc_args
		// causes subcommand validation to reject them as "unknown" parameters.
		$runtime_keys = array_keys(
			array_filter(
				WP_CLI::get_configurator()->get_spec(),
				static function ( $details ) {
					return false !== $details['runtime'];
				}
			)
		);
		foreach ( $alias_config as $key => $_ ) {
			if ( in_array( $key, $runtime_keys, true ) ) {
				continue;
			}
			if ( isset( $orig_config[ (string) $key ] ) && ! is_null( $orig_config[ (string) $key ] ) ) {
				// @phpstan-ignore assign.propertyType
				$this->assoc_args[ (string) $key ] = $orig_config[ (string) $key ];
			}
		}
	}
PHP;

if ( false === strpos( $contents, $old ) ) {
	// The original code was not found – the upstream may have already fixed
	// this or the file structure changed.  Either way, do nothing.
	return;
}

$patched = str_replace( $old, $new, $contents );
file_put_contents( $file, $patched );
