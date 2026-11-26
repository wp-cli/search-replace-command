Feature: Test search-replace --where option

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
  Scenario: Where clause with conflicting column restrictions
    Given a WP install
    And I run `wp post create --post_title='Title foobar' --post_name='testpost' --post_content='Content foobar' --post_excerpt='Excerpt foobar' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}

    # Use --where to limit to specific column and row condition
    When I try `wp search-replace 'foobar' 'replaced' --where='posts::post_status="publish"' --include-columns=post_title`
    Then STDERR should contain:
      """
      Warning: Column wildcard (*) was passed to --where. But --include-columns will still restrict replacements to columns: post_title
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

  @require-mysql
  Scenario: Where specifications with and without columns for different tables
    Given a WP install
    And I run `wp post create --post_title='Title foo' --post_content='Content foo' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}
    And I run `wp option add test_option 'option_foo'`

    When I run `wp search-replace 'foo' 'bar' --where='posts:post_title:post_status="publish";options::option_name="test_option"'`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Title bar
      """

    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      Content foo
      """

    When I run `wp option get test_option`
    Then STDOUT should be:
      """
      option_bar
      """

  @require-mysql
  Scenario: Where conditions with OR and with LIKE patterns
    Given a WP install
    And I run `wp post create --post_title='Foo sale' --post_status='publish' --porcelain`
    And save STDOUT as {SALE_ID}
    And I run `wp post create --post_title='Foo other' --post_status='publish' --porcelain`
    And save STDOUT as {OTHER_ID}
    And I run `wp post create --post_title='nothing here' --post_status='private' --porcelain`

    When I run `wp search-replace 'Foo' 'Bar' --where='posts::post_status="publish" OR post_status="private"' --dry-run`
    Then STDOUT should contain:
      """
      Success: 2 replacements to be made.
      """

    When I run `wp search-replace 'Foo' 'Bar' --where='posts::post_title LIKE "%sale%"'`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

    When I run `wp post get {SALE_ID} --field=title`
    Then STDOUT should be:
      """
      Bar sale
      """

    When I run `wp post get {OTHER_ID} --field=title`
    Then STDOUT should be:
      """
      Foo other
      """

  @require-mysql
  Scenario: Where clause with dry-run and a search string that differs when JSON-encoded
    Given a WP install
    And I run `wp post create --post_title='http://Foo.test published' --post_status='publish' --porcelain`
    And I run `wp post create --post_title='http://Foo.test draft' --post_status='draft' --porcelain`

    When I run `wp search-replace 'http://Foo.test' 'http://bar.test' wp_posts --where='posts::post_status="publish"' --dry-run`
    Then STDOUT should contain:
      """
      Success: 1 replacement to be made.
      """

  @require-mysql
  Scenario: Where conditions with semicolons inside quoted literals
    Given a WP install
    And I run `wp option update blogname 'Site foo'`
    And I run `wp post create --post_title='a;b foo' --porcelain`
    And save STDOUT as {POST1_ID}
    And I run `wp post create --post_title="it's;c foo" --porcelain`
    And save STDOUT as {POST2_ID}
    And I run `wp post create --post_title="it's;d foo" --porcelain`
    And save STDOUT as {POST3_ID}
    And I run `wp post create --post_title='other foo' --porcelain`
    And save STDOUT as {POST4_ID}

    When I run `wp search-replace foo bar --where="posts:post_title:post_title IN ('a;b foo', 'it\'s;c foo', 'it''s;d foo');options:option_value:option_name = 'blogname'"`
    Then STDOUT should contain:
      """
      Success: Made 4 replacements.
      """

    When I run `wp post get {POST1_ID} --field=title`
    Then STDOUT should be:
      """
      a;b bar
      """

    When I run `wp post get {POST2_ID} --field=title`
    Then STDOUT should be:
      """
      it's;c bar
      """

    When I run `wp post get {POST3_ID} --field=title`
    Then STDOUT should be:
      """
      it's;d bar
      """

    When I run `wp post get {POST4_ID} --field=title`
    Then STDOUT should be:
      """
      other foo
      """

    When I run `wp option get blogname`
    Then STDOUT should be:
      """
      Site bar
      """

  @require-mysql
  Scenario: Malformed where specifications are rejected before any table is processed
    Given a WP install
    And I run `wp post create --post_title='Post foo' --porcelain`
    And save STDOUT as {POST_ID}

    When I try `wp search-replace foo bar --where='wp_posts:post_title'`
    Then STDERR should be:
      """
      Error: Invalid --where specification 'wp_posts:post_title'. Expected format: <table>[,table]:[column,...]:<SQL-condition>.
      """
    And the return code should be 1

    When I try `wp search-replace foo bar --where='posts::1=1;wp_postmeta:meta_value'`
    Then STDERR should be:
      """
      Error: Invalid --where specification 'wp_postmeta:meta_value'. Expected format: <table>[,table]:[column,...]:<SQL-condition>.
      """
    And the return code should be 1

    When I try `wp search-replace foo bar --where=":post_title:1=1"`
    Then STDERR should be:
      """
      Error: Invalid --where specification ':post_title:1=1': no table given.
      """
    And the return code should be 1

    When I try `wp search-replace foo bar --where="posts::post_title = 'Post foo"`
    Then STDERR should be:
      """
      Error: Invalid --where specification 'posts::post_title = 'Post foo': unterminated ' quote.
      """
    And the return code should be 1

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Post foo
      """

  @require-mysql
  Scenario: Where condition of 0 matches no rows
    Given a WP install
    And I run `wp post create --post_title='Post foo' --porcelain`
    And save STDOUT as {POST_ID}

    When I run `wp search-replace foo bar --where='wp_posts:post_title:0'`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """

    When I run `wp search-replace foo bar --where='wp_posts:post_title:0' --precise`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Post foo
      """

  @require-mysql
  Scenario Outline: Where condition selects the rows before any column is replaced
    Given a WP install
    And I run `wp post create --post_title='Title foo' --post_content='Content foo' --porcelain`
    And save STDOUT as {MATCH_ID}
    And I run `wp post create --post_title='Other foo' --post_content='Other none' --porcelain`
    And save STDOUT as {OTHER_ID}

    When I run `wp search-replace foo bar --where='<where>' --dry-run --format=count <flags>`
    Then STDOUT should be:
      """
      2
      """

    When I run `wp search-replace foo bar --where='<where>' --format=count <flags>`
    Then STDOUT should be:
      """
      2
      """

    When I run `wp post get {MATCH_ID} --field=title`
    Then STDOUT should be:
      """
      Title bar
      """

    When I run `wp post get {MATCH_ID} --field=content`
    Then STDOUT should be:
      """
      Content bar
      """

    When I run `wp post get {OTHER_ID} --field=title`
    Then STDOUT should be:
      """
      Other foo
      """

    Examples:
      | where                                                                            | flags     |
      | posts:post_content,post_title:post_content LIKE "%foo%"                          |           |
      | posts:post_content,post_title:post_content LIKE "%foo%"                          | --precise |
      | posts:post_title:post_content LIKE "%foo%";posts:post_content:post_title LIKE "%foo%" |           |
      | posts:post_title:post_content LIKE "%foo%";posts:post_content:post_title LIKE "%foo%" | --precise |

  Scenario: Where clause cannot be combined with an export
    Given a WP install

    When I try `wp search-replace 'foo' 'bar' --where='posts::post_status="publish"' --export=out.sql`
    Then STDERR should be:
      """
      Error: You cannot supply --where or --no-revisions together with --export.
      """
    And the return code should be 1
