Feature: Test search-replace --callback option

  @require-mysql
  Scenario: Search replace with callback function
    Given a WP install
    And a callback-function.php file:
      """
      <?php
      function test_callback( $data, $replacement ) {
        return str_replace( 'foo', strtoupper( $replacement ), $data );
      }
      """
    And I run `wp post create --post_title='foo bar' --post_content='foo content' --porcelain`
    And save STDOUT as {POST_ID}

    When I run `wp search-replace 'foo' 'baz' wp_posts --callback='test_callback' --precise --require=callback-function.php`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """
    And STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_title   | 1            | PHP  |
      | wp_posts | post_content | 1            | PHP  |

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      BAZ bar
      """

    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      BAZ content
      """

  @require-mysql
  Scenario: Search replace with callback function and regex
    Given a WP install
    And a callback-regex.php file:
      """
      <?php
      function regex_callback( $data, $replacement, $search_regex ) {
        // Replace matched digits with their square
        return preg_replace_callback( $search_regex, function( $matches ) {
          $num = (int)$matches[1];
          return $num * $num;
        }, $data );
      }
      """
    And I run `wp post create --post_title='Number 5 test' --porcelain`
    And save STDOUT as {POST_ID}

    When I run `wp search-replace 'Number ([0-9]+)' 'ignored' --regex --callback='regex_callback' --precise --require=callback-regex.php`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      25 test
      """

  @require-mysql
  Scenario: Search replace with callback function that doesn't exist
    Given a WP install

    When I try `wp search-replace 'foo' 'bar' --callback='nonexistent_function' --precise`
    Then STDERR should be:
      """
      Error: The callback function does not exist. Skipping operation.
      """
    And the return code should be 1

  @require-mysql
  Scenario: Search replace with callback requires precise mode
    Given a WP install
    And a callback-function.php file:
      """
      <?php
      function test_callback( $data, $replacement ) {
        return str_replace( 'foo', strtoupper( $replacement ), $data );
      }
      """

    When I try `wp search-replace 'foo' 'bar' --callback='test_callback' --no-precise --require=callback-function.php`
    Then STDERR should be:
      """
      Error: PHP is required to execute a callback function. --no-precise cannot be set.
      """
    And the return code should be 1

  @require-mysql
  Scenario: Callback function with regex search parameter
    Given a WP install
    And a regex-aware-callback.php file:
      """
      <?php
      function regex_aware_callback( $data, $replacement, $search_regex ) {
        // If regex is provided, use preg_replace, otherwise use str_replace
        if ( !empty( $search_regex ) ) {
          return preg_replace( $search_regex, $replacement . '_regex', $data );
        }
        return str_replace( 'foo', $replacement, $data );
      }
      """
    And I run `wp post create --post_title='foo title' --post_content='foo content' --porcelain`
    And save STDOUT as {POST_ID}

    When I run `wp search-replace 'foo' 'bar' wp_posts --callback='regex_aware_callback' --precise --require=regex-aware-callback.php`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      bar title
      """

    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      bar content
      """
