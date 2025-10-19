Feature: Test search-replace --revisions option

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
