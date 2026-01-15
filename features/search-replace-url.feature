Feature: URL-optimized search/replace with smart column skipping

  @require-mysql
  Scenario: Basic URL search/replace with smart column skipping
    Given a WP install

    When I run `wp post create --post_title="Test Post" --post_content="Visit http://example.test for more" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace 'http://example.test' 'http://example.com' --smart-url --dry-run --verbose`
    Then STDOUT should contain:
      """
      Smart URL mode
      """
    And STDOUT should contain:
      """
      wp_posts
      """
    And STDOUT should contain:
      """
      post_content
      """

  @require-mysql
  Scenario: Smart mode skips non-URL columns
    Given a WP install

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' --dry-run --verbose`
    Then STDOUT should contain:
      """
      Smart URL mode: Skipping
      """
    And STDOUT should contain:
      """
      columns:
      """

  @require-mysql
  Scenario: Non-URL search does not trigger smart mode
    Given a WP install

    When I run `wp search-replace 'foo' 'bar' --dry-run`
    Then STDOUT should not contain:
      """
      Smart URL mode
      """
    And STDOUT should not contain:
      """
      Detected URL replacement
      """

  @require-mysql
  Scenario: URL replacement in post content
    Given a WP install

    When I run `wp post create --post_title="Test Post" --post_content="Visit http://oldsite.test for more info" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://oldsite.test' 'http://newsite.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http://newsite.com
      """
    And STDOUT should not contain:
      """
      http://oldsite.test
      """

  @require-mysql
  Scenario: URL replacement with skip-columns
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="http://example.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' --skip-columns=guid --dry-run`
    Then STDOUT should not contain:
      """
      | wp_posts | guid |
      """

  @require-mysql
  Scenario: URL replacement with include-columns
    Given a WP install

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' --include-columns=post_content --dry-run`
    Then STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 0            | SQL  |

  @require-mysql
  Scenario: Multisite URL replacement
    Given a WP multisite install
    And I run `wp site create --slug="foo" --title="foo" --email="foo@example.com"`

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' --network --dry-run`
    Then STDOUT should contain:
      """
      wp_blogs
      """

  @require-mysql
  Scenario: URL replacement with export
    Given a WP install
    And an empty cache

    When I run `wp post create --post_title="Test" --post_content="http://oldurl.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://oldurl.test' 'http://newurl.com' --export`
    Then STDOUT should contain:
      """
      INSERT INTO
      """
    And STDOUT should contain:
      """
      http://newurl.com
      """

  @require-mysql
  Scenario: URL replacement in options table
    Given a WP install

    When I run `wp option add test_url 'http://testsite.test/page' --autoload=no`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp search-replace --smart-url 'http://testsite.test' 'http://testsite.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp option get test_url`
    Then STDOUT should be:
      """
      http://testsite.com/page
      """

  @require-mysql
  Scenario: URL replacement in post meta
    Given a WP install

    When I run `wp post create --post_title="Test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp post meta add {POST_ID} custom_url 'http://meta.test/path'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp search-replace --smart-url 'http://meta.test' 'http://meta.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp post meta get {POST_ID} custom_url`
    Then STDOUT should be:
      """
      http://meta.com/path
      """

  @require-mysql
  Scenario: URL replacement in comments
    Given a WP install

    When I run `wp post create --post_title="Test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp comment create --comment_post_ID={POST_ID} --comment_content="Check http://comment.test" --comment_author="Test" --comment_author_email="test@test.com" --porcelain`
    Then save STDOUT as {COMMENT_ID}

    When I run `wp search-replace --smart-url 'http://comment.test' 'http://comment.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp comment get {COMMENT_ID} --field=comment_content`
    Then STDOUT should contain:
      """
      http://comment.com
      """

  @require-mysql
  Scenario: Dry run does not modify database
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="http://dryrun.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://dryrun.test' 'http://dryrun.com' --dry-run`
    Then STDOUT should match /replacement(s)? to be made/

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http://dryrun.test
      """

  @require-mysql
  Scenario: Report changed only
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="http://report.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://report.test' 'http://report.com' --report-changed-only --dry-run`
    Then STDOUT should contain:
      """
      post_content
      """
    And STDOUT should not contain:
      """
      | wp_posts | post_type | 0 |
      """

  @require-mysql
  Scenario: Skip tables option
    Given a WP install

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' --skip-tables=wp_posts --dry-run`
    Then STDOUT should not contain:
      """
      wp_posts
      """
    And STDOUT should contain:
      """
      wp_options
      """

  @require-mysql
  Scenario: Specific tables only
    Given a WP install

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' wp_posts --dry-run`
    Then STDOUT should contain:
      """
      wp_posts
      """
    And STDOUT should not contain:
      """
      wp_options
      """

  @require-mysql
  Scenario: HTTP to HTTPS conversion
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="Visit http://secure.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://secure.test' 'https://secure.test'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      https://secure.test
      """

  @require-mysql
  Scenario: Advanced table analysis mode
    Given a WP install

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' --analyze-tables --dry-run --verbose`
    Then STDOUT should contain:
      """
      Analyzing table structures
      """
    And STDOUT should contain:
      """
      Smart URL mode with table analysis
      """

  @require-mysql
  Scenario: Table analysis skips integer columns
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_test_table (id INT PRIMARY KEY, name VARCHAR(255), count BIGINT, url TEXT)"`

    When I run `wp db query "INSERT INTO wp_test_table VALUES (1, 'test', 100, 'http://test.url')"`
    Then STDERR should be empty

    When I run `wp search-replace --smart-url 'http://test.url' 'http://new.url' wp_test_table --analyze-tables --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp db query "SELECT url FROM wp_test_table WHERE id = 1" --skip-column-names`
    Then STDOUT should contain:
      """
      http://new.url
      """

    When I run `wp db query "DROP TABLE wp_test_table"`
    Then STDERR should be empty

  @require-mysql
  Scenario: Table analysis skips enum columns
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_test_enum (id INT PRIMARY KEY, status ENUM('active','inactive'), data TEXT)"`

    When I run `wp db query "INSERT INTO wp_test_enum VALUES (1, 'active', 'http://enum.test')"`
    Then STDERR should be empty

    When I run `wp search-replace --smart-url 'http://enum.test' 'http://enum.com' wp_test_enum --analyze-tables --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp db query "SELECT data FROM wp_test_enum WHERE id = 1" --skip-column-names`
    Then STDOUT should contain:
      """
      http://enum.com
      """

    When I run `wp db query "DROP TABLE wp_test_enum"`
    Then STDERR should be empty

  @require-mysql
  Scenario: Table analysis skips date columns
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_test_dates (id INT PRIMARY KEY, created_date DATE, url VARCHAR(255))"`

    When I run `wp db query "INSERT INTO wp_test_dates VALUES (1, '2024-01-01', 'http://date.test')"`
    Then STDERR should be empty

    When I run `wp search-replace --smart-url 'http://date.test' 'http://date.com' wp_test_dates --analyze-tables --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp db query "SELECT url FROM wp_test_dates WHERE id = 1" --skip-column-names`
    Then STDOUT should contain:
      """
      http://date.com
      """

    When I run `wp db query "DROP TABLE wp_test_dates"`
    Then STDERR should be empty

  @require-mysql
  Scenario: Table analysis with pattern matching
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_test_patterns (order_id INT PRIMARY KEY, order_count INT, order_status VARCHAR(20), order_url TEXT)"`

    When I run `wp db query "INSERT INTO wp_test_patterns VALUES (1, 5, 'pending', 'http://pattern.test')"`
    Then STDERR should be empty

    When I run `wp search-replace --smart-url 'http://pattern.test' 'http://pattern.com' wp_test_patterns --analyze-tables --all-tables-with-prefix --verbose`
    Then STDOUT should contain:
      """
      Analyzing table structures
      """

    When I run `wp db query "SELECT order_url FROM wp_test_patterns WHERE order_id = 1" --skip-column-names`
    Then STDOUT should contain:
      """
      http://pattern.com
      """

    When I run `wp db query "DROP TABLE wp_test_patterns"`
    Then STDERR should be empty

  @require-mysql
  Scenario: Serialized data handling
    Given a WP install

    When I run `wp post create --post_title="Test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp post meta add {POST_ID} serialized_data 'a:2:{s:3:"url";s:18:"http://serial.test";s:4:"name";s:4:"test";}'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp db query "SELECT meta_value FROM wp_postmeta WHERE meta_key = 'serialized_data' AND post_id = {POST_ID}" --skip-column-names`
    Then STDOUT should contain:
      """
      http://serial.test
      """

    When I run `wp search-replace --smart-url 'http://serial.test' 'http://serial.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp db query "SELECT meta_value FROM wp_postmeta WHERE meta_key = 'serialized_data' AND post_id = {POST_ID}" --skip-column-names`
    Then STDOUT should contain:
      """
      http://serial.com
      """

  @require-mysql
  Scenario: Large content replacement
    Given a WP install

    When I run `wp post create --post_title="Large Post" --post_content="$(printf 'http://large.test %.0s' {1..1000})" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://large.test' 'http://large.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http://large.com
      """
    And STDOUT should not contain:
      """
      http://large.test
      """

  @require-mysql
  Scenario: Multiple URL replacements in same content
    Given a WP install

    When I run `wp post create --post_title="Multi URL" --post_content="Visit http://multi.test and also http://multi.test/page" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://multi.test' 'http://multi.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http://multi.com
      """
    And STDOUT should contain:
      """
      http://multi.com/page
      """

  @require-mysql
  Scenario: Verbose output shows progress
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="http://verbose.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://verbose.test' 'http://verbose.com' --verbose`
    Then STDOUT should contain:
      """
      Checking:
      """

  @require-mysql
  Scenario: Count format output
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="http://count.test http://count.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --smart-url 'http://count.test' 'http://count.com' --format=count`
    Then STDOUT should be a number

  @require-mysql
  Scenario: All tables with prefix
    Given a WP install

    When I run `wp search-replace --smart-url 'http://example.test' 'http://example.com' --all-tables-with-prefix --dry-run`
    Then STDOUT should contain:
      """
      wp_
      """

  @require-mysql
  Scenario: Recurse objects option
    Given a WP install

    When I run `wp post create --post_title="Test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp post meta add {POST_ID} object_data '{"url":"http://object.test","nested":{"url":"http://object.test/nested"}}'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp search-replace --smart-url 'http://object.test' 'http://object.com' --recurse-objects`
    Then STDOUT should contain:
      """
      Success:
      """

  @require-mysql
  Scenario: Auto-detect http:// URL and enable smart mode
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="Visit http://autodetect.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace 'http://autodetect.test' 'http://autodetect.com' --dry-run`
    Then STDOUT should contain:
      """
      Detected URL replacement
      """
    And STDOUT should contain:
      """
      Automatically enabling smart-url mode
      """

  @require-mysql
  Scenario: Auto-detect https:// URL and enable smart mode
    Given a WP install

    When I run `wp post create --post_title="Test" --post_content="Visit https://secure.test" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace 'https://secure.test' 'https://secure.com'`
    Then STDOUT should contain:
      """
      Detected URL replacement
      """
    And STDOUT should contain:
      """
      Made
      """

  @require-mysql
  Scenario: Auto-detect shows skipped columns in verbose mode
    Given a WP install

    When I run `wp search-replace 'http://verbose.test' 'http://verbose.com' --dry-run --verbose`
    Then STDOUT should contain:
      """
      Detected URL replacement
      """
    And STDOUT should contain:
      """
      Smart URL mode: Skipping
      """
    And STDOUT should contain:
      """
      columns:
      """

  @require-mysql
  Scenario: Regex mode disables auto-detection
    Given a WP install

    When I run `wp search-replace 'http://regex\.test' 'http://regex.com' --regex --dry-run`
    Then STDOUT should not contain:
      """
      Detected URL replacement
      """
    And STDOUT should not contain:
      """
      Smart URL mode
      """

  @require-mysql
  Scenario: Explicit --smart-url flag still works
    Given a WP install

    When I run `wp search-replace 'http://explicit.test' 'http://explicit.com' --smart-url --dry-run`
    Then STDOUT should not contain:
      """
      Detected URL replacement
      """
    And STDOUT should contain:
      """
      replacements to be made
      """

  @require-mysql
  Scenario: Auto-detection with actual URL replacement
    Given a WP install

    When I run `wp post create --post_title="Auto Test" --post_content="Check http://replace.test for info" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace 'http://replace.test' 'http://replace.com'`
    Then STDOUT should contain:
      """
      Detected URL replacement
      """

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http://replace.com
      """
    And STDOUT should not contain:
      """
      http://replace.test
      """

  @require-mysql
  Scenario: Error when --smart-url used with non-URL string
    Given a WP install

    When I try `wp search-replace --smart-url 'foo' 'bar'`
    Then STDERR should contain:
      """
      Error: The --smart-url flag is designed for URL replacements, but "foo" is not a valid URL.
      """
    And the return code should be 1

  @require-mysql
  Scenario: Error when auto-detection would enable smart-url for invalid URL format
    Given a WP install

    When I try `wp search-replace 'http://invalid url with spaces' 'http://valid.com'`
    Then STDERR should contain:
      """
      Error: The --smart-url flag is designed for URL replacements, but "http://invalid url with spaces" is not a valid URL.
      """
    And the return code should be 1

  @require-mysql
  Scenario: Error when --analyze-tables used without --smart-url
    Given a WP install

    When I try `wp search-replace 'foo' 'bar' --analyze-tables`
    Then STDERR should contain:
      """
      Error: The --analyze-tables flag requires --smart-url to be enabled.
      """
    And the return code should be 1

  @require-mysql
  Scenario: Table analysis skips SET columns
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_test_set (id INT PRIMARY KEY, permissions SET('read','write','delete'), data TEXT)"`

    When I run `wp db query "INSERT INTO wp_test_set VALUES (1, 'read,write', 'http://set.test')"`
    Then STDERR should be empty

    When I run `wp search-replace --smart-url 'http://set.test' 'http://set.com' wp_test_set --analyze-tables --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp db query "SELECT data FROM wp_test_set WHERE id = 1" --skip-column-names`
    Then STDOUT should contain:
      """
      http://set.com
      """

    When I run `wp db query "DROP TABLE wp_test_set"`
    Then STDERR should be empty
