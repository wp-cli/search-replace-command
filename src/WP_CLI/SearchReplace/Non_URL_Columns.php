<?php
/**
 * Non-URL column detection for search-replace operations.
 *
 * This class provides both a static list of WordPress core columns that never
 * contain URLs, and dynamic analysis methods to detect non-URL columns based on
 * MySQL datatypes (integers, dates, enums, blobs, etc.) and common naming patterns
 * (*_id, *_count, *_status, is_*, has_*, etc.). Used by --smart-url and --analyze-tables.
 *
 * @package wp-cli/search-replace-command
 */

namespace WP_CLI\SearchReplace;

/**
 * Provides column skip lists for URL-specific search-replace operations.
 */
class Non_URL_Columns {

	/**
	 * MySQL column DATA_TYPE values that cannot safely/meaningfully contain URLs.
	 *
	 * Note: While binary columns technically could contain URL bytes, they are
	 * commonly used for non-text data (compressed/encrypted/binary) and should
	 * not be modified by string replacements.
	 */
	private const NON_TEXT_DATA_TYPES = array(
		// Numeric types.
		'tinyint',
		'smallint',
		'mediumint',
		'int',
		'bigint',
		'decimal',
		'numeric',
		'float',
		'double',
		'real',
		'bit',
		'boolean',
		'serial',

		// Date/time types.
		'date',
		'datetime',
		'timestamp',
		'time',
		'year',

		// Binary types.
		'binary',
		'varbinary',
		'tinyblob',
		'blob',
		'mediumblob',
		'longblob',
	);

	/**
	 * Regex patterns indicating a column name is unlikely to contain URLs.
	 */
	private const NON_URL_COLUMN_NAME_PATTERNS = array(
		'/^.*_id$/i',        // Ends with _id (user_id, post_id, order_id)
		'/^.*_count$/i',     // Ends with _count (view_count, item_count)
		'/^.*_status$/i',    // Ends with _status (payment_status, order_status)
		'/^.*_type$/i',      // Ends with _type (content_type, media_type)
		'/^.*_date$/i',      // Ends with _date (created_date, modified_date)
		'/^.*_time$/i',      // Ends with _time (start_time, end_time)
		'/^.*_flag$/i',      // Ends with _flag (active_flag, deleted_flag)
		'/^.*_number$/i',    // Ends with _number (order_number, invoice_number)
		'/^.*_amount$/i',    // Ends with _amount (total_amount, tax_amount)
		'/^.*_price$/i',     // Ends with _price (unit_price, sale_price)
		'/^.*_quantity$/i',  // Ends with _quantity (stock_quantity)
		'/^.*_rating$/i',    // Ends with _rating (average_rating)
		'/^.*_order$/i',     // Ends with _order (sort_order, display_order)
		'/^.*_index$/i',     // Ends with _index (sort_index)
		'/^.*_position$/i',  // Ends with _position (menu_position)
		'/^is_/i',           // Starts with is_ (is_active, is_deleted)
		'/^has_/i',          // Starts with has_ (has_children, has_thumbnail)
		'/^can_/i',          // Starts with can_ (can_edit, can_delete)
		'/^total_/i',        // Starts with total_ (total_sales, total_views)
		'/^num_/i',          // Starts with num_ (num_items, num_comments)
		'/^max_/i',          // Starts with max_ (max_length, max_size)
		'/^min_/i',          // Starts with min_ (min_length, min_size)
	);

	/**
	 * Get the list of columns that never contain URLs in WordPress core tables.
	 *
	 * @return string[] List of column names to skip.
	 */
	public static function get_core_columns() {
		return array(
			// wp_posts table - Status, type, and metadata columns
			'ID',
			'post_author',
			'post_date',
			'post_date_gmt',
			'post_status',
			'comment_status',
			'ping_status',
			'post_password',
			// Note: post_name is a slug (not a full URL) in normal WordPress usage.
			// In rare edge cases (e.g. imports) it may contain URL-like strings, but we
			// still treat it as non-URL for search/replace to keep this optimization simple.
			'post_name',
			'to_ping',
			'pinged',
			'post_modified',
			'post_modified_gmt',
			'post_parent',
			'menu_order',
			'post_type',
			'post_mime_type',
			'comment_count',

			// wp_postmeta table
			'meta_id',
			'post_id',

			// wp_comments table - IDs, status, type, and dates
			'comment_ID',
			'comment_post_ID',
			'comment_date',
			'comment_date_gmt',
			'comment_karma',
			'comment_approved',
			'comment_type',
			'comment_parent',
			'user_id',

			// wp_commentmeta table
			'comment_id',

			// wp_users table - User metadata and status
			'user_login',
			'user_pass',
			'user_nicename',
			'user_email',
			'user_registered',
			'user_status',
			'display_name',

			// wp_usermeta table
			'umeta_id',

			// wp_terms table
			'term_id',
			'slug',
			'term_group',

			// wp_term_taxonomy table
			'term_taxonomy_id',
			'taxonomy',
			'parent',
			'count',

			// wp_term_relationships table
			'object_id',
			'term_order',

			// wp_options table
			'option_id',
			'autoload',

			// wp_links table
			'link_id',
			'link_visible',
			'link_owner',
			'link_rating',
			'link_updated',
			'link_rel',
			'link_rss',

			// wp_blogs table (multisite)
			'blog_id',
			'site_id',
			'registered',
			'last_updated',
			'public',
			'archived',
			'mature',
			'spam',
			'deleted',
			'lang_id',

			// wp_registration_log table (multisite)
			'IP',
			'email',
			'date_registered',

			// wp_signups table (multisite)
			'signup_id',
			'activated',
			'active',
		);
	}

	/**
	 * Check if a column datatype cannot contain URLs (or is unsafe to modify).
	 *
	 * @param string $data_type   MySQL DATA_TYPE (e.g., 'int', 'varchar').
	 * @param string $column_type Full COLUMN_TYPE (e.g., 'int(11)', 'enum(...)').
	 * @return bool True if the datatype cannot contain URLs.
	 */
	public static function is_non_text_datatype( $data_type, $column_type ) {
		$data_type_lc   = strtolower( $data_type );
		$column_type_lc = strtolower( $column_type );

		// Enum and set types (typically status/flag fields).
		if ( 0 === strpos( $column_type_lc, 'enum(' ) ) {
			return true;
		}

		if ( 0 === strpos( $column_type_lc, 'set(' ) ) {
			return true;
		}

		return in_array( $data_type_lc, self::NON_TEXT_DATA_TYPES, true );
	}

	/**
	 * Check if a column name matches patterns that indicate it cannot contain URLs.
	 *
	 * @param string $column_name The column name to check.
	 * @return bool True if the column name matches a non-URL pattern.
	 */
	public static function matches_non_url_pattern( $column_name ) {
		foreach ( self::NON_URL_COLUMN_NAME_PATTERNS as $pattern ) {
			if ( preg_match( $pattern, $column_name ) ) {
				return true;
			}
		}

		return false;
	}
}
