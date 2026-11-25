Feature: Test search-replace --revisions option

  @require-mysql
  Scenario: Search replace without revisions (--no-revisions)
    Given a WP install

    When I run `wp post create --post_title='Published foo' --post_name='1' --post_status='publish' --porcelain`
    Then save STDOUT as {PUBLISHED_ID}

    When I run `wp post create --post_title='Draft foo' --post_status='draft' --porcelain`
    Then save STDOUT as {DRAFT_ID}

    When I run `wp post create --post_title='Revision foo' --post_type='revision' --post_status='inherit' --post_parent={PUBLISHED_ID} --post_name='{PUBLISHED_ID}-revision-v1' --porcelain`
    Then save STDOUT as {REVISION_ID}

    When I run `wp post meta add {PUBLISHED_ID} test_key 'published_foo_meta'`
    Then STDOUT should not be empty

    When I run `wp post meta add {DRAFT_ID} test_key 'draft_foo_meta'`
    Then STDOUT should not be empty

    # add_post_meta() would store the meta on the parent post, not the revision.
    When I run `wp eval 'add_metadata( "post", {REVISION_ID}, "test_key", "revision_foo_meta" );'`
    And I run `wp option add test_option 'option_foo'`
    And I run `wp search-replace 'foo' 'bar' --no-revisions`
    Then STDOUT should contain:
      """
      Success: Made
      """

    When I run `wp post get {PUBLISHED_ID} --field=title`
    Then STDOUT should be:
      """
      Published bar
      """

    # Drafts are not revisions
    When I run `wp post get {DRAFT_ID} --field=title`
    Then STDOUT should be:
      """
      Draft bar
      """

    When I run `wp post get {REVISION_ID} --field=title`
    Then STDOUT should be:
      """
      Revision foo
      """

    When I run `wp post meta get {PUBLISHED_ID} test_key`
    Then STDOUT should be:
      """
      published_bar_meta
      """

    When I run `wp post meta get {DRAFT_ID} test_key`
    Then STDOUT should be:
      """
      draft_bar_meta
      """

    When I run `wp eval 'echo get_metadata( "post", {REVISION_ID}, "test_key", true );'`
    Then STDOUT should be:
      """
      revision_foo_meta
      """

    # Tables other than posts and postmeta are still processed
    When I run `wp option get test_option`
    Then STDOUT should be:
      """
      option_bar
      """

  @require-mysql
  Scenario: Search replace with default revisions behavior
    Given a WP install

    When I run `wp post create --post_title='Published fooooo' --post_name=1 --post_status='publish' --porcelain`
    Then save STDOUT as {PUBLISHED_ID}

    When I run `wp post create --post_title='Revision fooooo' --post_type='revision' --post_status='inherit' --post_parent={PUBLISHED_ID} --post_name='{PUBLISHED_ID}-revision-v1' --porcelain`
    Then save STDOUT as {REVISION_ID}

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

    When I run `wp post get {REVISION_ID} --field=title`
    Then STDOUT should be:
      """
      Revision baz
      """

  @require-mysql
  Scenario: Combining no-revisions with regex
    Given a WP install
    And I run `wp post create --post_title='Test foo123' --post_name='pubslug' --post_status='publish' --porcelain`
    And save STDOUT as {PUB_ID}
    And I run `wp post create --post_title='Test foo456' --post_type='revision' --post_status='inherit' --post_parent={PUB_ID} --post_name='{PUB_ID}-revision-v1' --porcelain`
    And save STDOUT as {REVISION_ID}

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

    When I run `wp post get {REVISION_ID} --field=title`
    Then STDOUT should be:
      """
      Test foo456
      """

  @require-mysql
  Scenario: Excluding revisions on all sites of a network
    Given a WP multisite install
    And I run `wp site create --slug=second --porcelain`
    And I run `wp post create --url=example.com/second --post_title='Second foo' --post_name='secondslug' --post_status='publish' --porcelain`
    And save STDOUT as {POST_ID}
    And I run `wp post create --url=example.com/second --post_title='Second revision foo' --post_type='revision' --post_status='inherit' --post_parent={POST_ID} --post_name='{POST_ID}-revision-v1' --porcelain`
    And save STDOUT as {REVISION_ID}

    When I run `wp search-replace 'foo' 'bar' --network --no-revisions`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp post get {POST_ID} --url=example.com/second --field=title`
    Then STDOUT should be:
      """
      Second bar
      """

    When I run `wp post get {REVISION_ID} --url=example.com/second --field=title`
    Then STDOUT should be:
      """
      Second revision foo
      """

  Scenario: Excluding revisions cannot be combined with an export
    Given a WP install

    When I try `wp search-replace 'foo' 'bar' --no-revisions --export=out.sql`
    Then STDERR should be:
      """
      Error: You cannot supply --where or --no-revisions together with --export.
      """
    And the return code should be 1
