Feature: Test new search-replace options (--callback, --revisions, --where)

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
  Scenario: Search replace without revisions (--no-revisions)
    Given a WP install

    When I run `wp post create --post_title='Published foo' --post_name='1' --post_status='publish' --porcelain`
    Then save STDOUT as {PUBLISHED_ID}

    When I run `wp post create --post_title='Draft foo' --post_status='draft' --porcelain`
    Then save STDOUT as {DRAFT_ID}

    When I run `wp post meta add {PUBLISHED_ID} test_key 'published_foo_meta'`
    Then STDOUT should not be empty

    When I run `wp post meta add {DRAFT_ID} test_key 'draft_foo_meta'`
    Then STDOUT should not be empty

    When I run `wp search-replace 'foo' 'bar' --no-revisions`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """

    # Verify published post was changed
    When I run `wp post get {PUBLISHED_ID} --field=title`
    Then STDOUT should be:
      """
      Published bar
      """

    # Verify draft post was NOT changed
    When I run `wp post get {DRAFT_ID} --field=title`
    Then STDOUT should be:
      """
      Draft foo
      """

    # Verify published post meta was changed
    When I run `wp post meta get {PUBLISHED_ID} test_key`
    Then STDOUT should be:
      """
      published_bar_meta
      """

    # Verify draft post meta was NOT changed
    When I run `wp post meta get {DRAFT_ID} test_key`
    Then STDOUT should be:
      """
      draft_foo_meta
      """

  @require-mysql
  Scenario: Search replace with default revisions behavior
    Given a WP install

    When I run `wp post create --post_title='Published fooooo' --post_name=1 --post_status='publish' --porcelain`
    Then save STDOUT as {PUBLISHED_ID}

    When I run `wp post create --post_title='Draft fooooo' --post_name=2 --post_status='draft' --porcelain`
    Then save STDOUT as {DRAFT_ID}

    # With default behavior (--revisions=true), both should be changed
    When I run `wp search-replace 'fooooo' 'baz'`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """

    When I run `wp post get {PUBLISHED_ID} --field=title`
    Then STDOUT should be:
      """
      Published baz
      """

    When I run `wp post get {DRAFT_ID} --field=title`
    Then STDOUT should be:
      """
      Draft baz
      """

  @require-mysql
  Scenario: Search replace with where clause on single table
    Given a WP install
    And I run `wp post create --post_title='Test foo 1' --post_name=1 --post_status='publish' --porcelain`
    And save STDOUT as {POST1_ID}
    And I run `wp post create --post_title='Test foo 2' --post_name=2 --post_status='draft' --porcelain`
    And save STDOUT as {POST2_ID}

    When I run `wp search-replace 'foo' 'bar' --where='posts::post_status="publish"'`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    # Verify published post was changed
    When I run `wp post get {POST1_ID} --field=title`
    Then STDOUT should be:
      """
      Test bar 1
      """

    # Verify draft post was NOT changed
    When I run `wp post get {POST2_ID} --field=title`
    Then STDOUT should be:
      """
      Test foo 2
      """

  @require-mysql
  Scenario: Search replace with where clause on specific column
    Given a WP install
    And I run `wp post create --post_title='Title xyzfoo' --post_name=1 --post_content='Content xyzfoo' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}

    # Only replace in post_title column where post_status is publish
    When I run `wp search-replace 'xyzfoo' 'bar' --where='posts:post_title:post_status="publish"'`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Title bar
      """

    # Content should remain unchanged since we specified only post_title column
    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      Content xyzfoo
      """

  @require-mysql
  Scenario: Search replace with where clause using IN subquery
    Given a WP install
    And I run `wp post create --post_title='Post foo' --post_status='publish' --porcelain`
    And save STDOUT as {PUBLISHED_ID}
    And I run `wp post create --post_title='Draft foo' --post_status='draft' --porcelain`
    And save STDOUT as {DRAFT_ID}
    And I run `wp post meta add {PUBLISHED_ID} key1 'value_foo'`
    And I run `wp post meta add {DRAFT_ID} key1 'value_foo'`

    # Only replace postmeta where post_id is in published posts
    When I run `wp search-replace 'foo' 'bar' wp_postmeta --where='postmeta::post_id IN (SELECT ID FROM wp_posts WHERE post_status="publish")'`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    # Check published post's meta was changed
    When I run `wp post meta get {PUBLISHED_ID} key1`
    Then STDOUT should be:
      """
      value_bar
      """

    # Check draft post's meta was NOT changed
    When I run `wp post meta get {DRAFT_ID} key1`
    Then STDOUT should be:
      """
      value_foo
      """

  @require-mysql
  Scenario: Search replace with multiple where specifications
    Given a WP install
    And I run `wp post create --post_title='Pub foo' --post_name='pubpost' --post_status='publish' --porcelain`
    And save STDOUT as {PUB_ID}
    And I run `wp post create --post_title='Draft foo' --post_name='draftpost' --post_status='draft' --porcelain`
    And save STDOUT as {DRAFT_ID}
    And I run `wp option set test_option 'option_foo'`

    # Multiple where specs: posts must be published, options with specific name pattern
    When I run `wp search-replace 'foo' 'bar' --where='posts::post_status="publish";options::option_name LIKE "test_%"'`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """

    When I run `wp post get {PUB_ID} --field=title`
    Then STDOUT should be:
      """
      Pub bar
      """

    When I run `wp post get {DRAFT_ID} --field=title`
    Then STDOUT should be:
      """
      Draft foo
      """

    When I run `wp option get test_option`
    Then STDOUT should be:
      """
      option_bar
      """

  @require-mysql
  Scenario: Search replace with where clause on multiple tables
    Given a WP install
    And I run `wp post create --post_title='Post fooooo' --post_name='postslug' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}
    And I run `wp post meta add {POST_ID} testmeta 'meta_fooooo'`
    And I run `wp option set opt_name 'opt_fooooo'`

    # Apply where to posts (published only) and postmeta (where meta_key LIKE 'test%')
    # This should match the post_title and the testmeta value
    When I run `wp search-replace 'fooooo' 'bar' --where='posts::post_status="publish";postmeta::meta_key LIKE "test%"'`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Post bar
      """

    When I run `wp post meta get {POST_ID} testmeta`
    Then STDOUT should be:
      """
      meta_bar
      """

    # Options should not be affected by posts/postmeta where clause
    When I run `wp option get opt_name`
    Then STDOUT should be:
      """
      opt_fooooo
      """

  @require-mysql
  Scenario: Search replace combining where with dry-run
    Given a WP install
    And I run `wp post create --post_title='Test foo' --post_name='testslug' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}
    And I run `wp post create --post_title='Draft foo' --post_name='draftslug' --post_status='draft' --porcelain`
    And save STDOUT as {DRAFT_ID}

    When I run `wp search-replace 'foo' 'bar' --where='posts::post_status="publish"' --dry-run`
    Then STDOUT should contain:
      """
      Success: 1 replacement to be made.
      """

    # Verify nothing was actually changed
    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Test foo
      """

    When I run `wp post get {DRAFT_ID} --field=title`
    Then STDOUT should be:
      """
      Draft foo
      """

  @require-mysql
  Scenario: Search replace with where clause using wildcards in table names
    Given a WP install
    And I run `wp post create --post_title='Post foo' --post_name='postname' --post_content='Content foo' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}
    And I run `wp post meta add {POST_ID} test_meta 'meta_foo'`

    # Use wildcard pattern for table matching with WHERE clause
    When I run `wp search-replace 'foo' 'bar' 'wp_post*' --where='posts::post_status="publish";postmeta::post_id IN (SELECT ID FROM wp_posts WHERE post_status="publish")'`
    Then STDOUT should contain:
      """
      Success: Made 3 replacements.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Post bar
      """

    When I run `wp post meta get {POST_ID} test_meta`
    Then STDOUT should be:
      """
      meta_bar
      """

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

  @require-mysql
  Scenario: Combining no-revisions with regex
    Given a WP install
    And I run `wp post create --post_title='Test foo123' --post_name='pubslug' --post_status='publish' --porcelain`
    And save STDOUT as {PUB_ID}
    And I run `wp post create --post_title='Test foo456' --post_name='draftslug' --post_status='draft' --porcelain`
    And save STDOUT as {DRAFT_ID}

    When I run `wp search-replace 'foo[0-9]+' 'bar999' --regex --no-revisions`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    When I run `wp post get {PUB_ID} --field=title`
    Then STDOUT should be:
      """
      Test bar999
      """

    When I run `wp post get {DRAFT_ID} --field=title`
    Then STDOUT should be:
      """
      Test foo456
      """

  @require-mysql
  Scenario: Where clause with conflicting column restrictions
    Given a WP install
    And I run `wp post create --post_title='Title foobar' --post_name='testpost' --post_content='Content foobar' --post_excerpt='Excerpt foobar' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}

    # Use --where to limit to specific column and row condition
    When I try `wp search-replace 'foobar' 'replaced' --where='posts::post_status="publish"' --include-columns=post_title`
    Then STDERR should contain:
      """
      Warning: Column-catch was passed to --where while. But --include-columns will still restrict replacements to columns: post_title
      """

    And STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    # Verify only title was changed
    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Title replaced
      """

    # Content should remain unchanged since we only specified post_title column
    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      Content foobar
      """

    # Now test --where to limit by status (create draft post)
    When I run `wp post create --post_title='Draft foobar' --post_name='draftpost' --post_status='draft' --porcelain`
    Then save STDOUT as {DRAFT_ID}

    # Replace only in published posts using --where
    When I run `wp search-replace 'replaced' 'final' --where='posts::post_status="publish"'`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Title final
      """

    # Draft post should remain unchanged
    When I run `wp post get {DRAFT_ID} --field=title`
    Then STDOUT should be:
      """
      Draft foobar
      """

  @require-mysql
  Scenario: Where clause with verbose output
    Given a WP install
    And I run `wp post create --post_title='Test foo' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}

    When I run `wp search-replace 'foo' 'bar' --where='posts::post_status="publish"' --verbose`
    Then STDOUT should contain:
      """
      Checking: wp_posts.post_title
      """
    And STDOUT should contain:
      """
      rows affected
      """
