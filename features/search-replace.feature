Feature: Do global search/replace

  @require-mysql
  Scenario: Basic search/replace
    Given a WP install

    When I run `wp search-replace foo bar`
    Then STDOUT should contain:
      """
      guid
      """

    When I run `wp search-replace foo bar --skip-tables=wp_posts`
    Then STDOUT should not contain:
      """
      wp_posts
      """

    When I run `wp search-replace foo bar --skip-tables=wp_post\*`
    Then STDOUT should not contain:
      """
      wp_posts
      """
    And STDOUT should not contain:
      """
      wp_postmeta
      """
    And STDOUT should contain:
      """
      wp_users
      """

    When I run `wp search-replace foo bar --skip-columns=guid`
    Then STDOUT should not contain:
      """
      guid
      """

    When I run `wp search-replace foo bar --include-columns=post_content`
    Then STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 0            | SQL  |

    When I run `wp search-replace foo bar --skip-columns=wp_posts.guid`
    Then STDOUT should not contain:
      """
      guid
      """

    When I run `wp search-replace foo bar --include-columns=wp_posts.post_content`
    Then STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 0            | SQL  |

  @require-mysql
  Scenario: Multisite search/replace
    Given a WP multisite install
    And I run `wp site create --slug="foo" --title="foo" --email="foo@example.com"`
    And I run `wp search-replace foo bar --network`
    Then STDOUT should be a table containing rows:
      | Table        | Column       | Replacements | Type |
      | wp_2_options | option_value | 4            | PHP  |
      | wp_blogs     | path         | 1            | SQL  |

  @require-mysql
  Scenario: Don't run on unregistered tables by default
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_awesome ( id int(11) unsigned NOT NULL AUTO_INCREMENT, awesome_stuff TEXT, PRIMARY KEY (id) ) ENGINE=InnoDB DEFAULT CHARSET=latin1;"`

    When I run `wp search-replace foo bar`
    Then STDOUT should not contain:
      """
      wp_awesome
      """

    When I run `wp search-replace foo bar --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      wp_awesome
      """

  @require-mysql
  Scenario: Skip views during search/replace
    Given a WP install
    And I run `wp db query "CREATE VIEW wp_posts_view AS SELECT ID, post_title FROM wp_posts;"`

    When I run `wp search-replace foo bar --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      wp_posts_view
      """
    And STDOUT should contain:
      """
      skipped (view)
      """

    When I run `wp search-replace foo bar --all-tables`
    Then STDOUT should contain:
      """
      wp_posts_view
      """
    And STDOUT should contain:
      """
      skipped (view)
      """

  @require-mysql
  Scenario: Run on unregistered, unprefixed tables with --all-tables flag
    Given a WP install
    And I run `wp db query "CREATE TABLE awesome_table ( id int(11) unsigned NOT NULL AUTO_INCREMENT, awesome_stuff TEXT, PRIMARY KEY (id) ) ENGINE=InnoDB DEFAULT CHARSET=latin1;"`

    When I run `wp search-replace foo bar`
    Then STDOUT should not contain:
      """
      awesome_table
      """

    When I run `wp search-replace foo bar --all-tables`
    Then STDOUT should contain:
      """
      awesome_table
      """

  @require-mysql
  Scenario: Run on all tables matching string with wildcard
    Given a WP install

    When I run `wp option set bar fooz`
    And I run `wp option get bar`
    Then STDOUT should be:
      """
      fooz
      """

    When I run `wp post create --post_title=bar --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp post meta add {POST_ID} fooz bar`
    Then STDOUT should not be empty

    When I run `wp search-replace bar burrito wp_post\?`
    Then STDOUT should be a table containing rows:
      | Table    | Column     | Replacements | Type |
      | wp_posts | post_title | 1            | SQL  |
    And STDOUT should not contain:
      """
      wp_options
      """

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      burrito
      """

    When I run `wp post meta get {POST_ID} fooz`
    Then STDOUT should be:
      """
      bar
      """

    When I run `wp option get bar`
    Then STDOUT should be:
      """
      fooz
      """

    When I try `wp search-replace fooz burrito wp_opt\*on`
    Then STDERR should be:
      """
      Error: Couldn't find any tables matching: wp_opt*on
      """
    And the return code should be 1

    When I run `wp search-replace fooz burrito wp_opt\* wp_postme\*`
    Then STDOUT should be a table containing rows:
      | Table       | Column       | Replacements | Type |
      | wp_options  | option_value | 1            | PHP  |
      | wp_postmeta | meta_key     | 1            | SQL  |
    And STDOUT should not contain:
      """
      wp_posts
      """

    When I run `wp option get bar`
    Then STDOUT should be:
      """
      burrito
      """

    When I run `wp post meta get {POST_ID} burrito`
    Then STDOUT should be:
      """
      bar
      """

  @require-mysql
  Scenario: Quiet search/replace
    Given a WP install

    When I run `wp search-replace foo bar --quiet`
    Then STDOUT should be empty

  @require-mysql
  Scenario: Verbose search/replace
    Given a WP install
    And I run `wp post create --post_title='Replace this text' --porcelain`
    And save STDOUT as {POSTID}

    When I run `wp search-replace 'Replace' 'Replaced' --verbose`
    Then STDOUT should contain:
      """
      Checking: wp_posts.post_title
      1 rows affected
      """

    When I run `wp search-replace 'Replace' 'Replaced' --verbose --precise`
    Then STDOUT should contain:
      """
      Checking: wp_posts.post_title
      1 rows affected
      """

  # See https://github.com/wp-cli/search-replace-command/issues/190
  Scenario: Regex search/replace
    Given a WP install
    When I run `wp search-replace '(Hello)\s(world)' '$2, $1' --regex`
    Then STDOUT should contain:
      """
      wp_posts
      """
    When I run `wp post list --fields=post_title`
    Then STDOUT should contain:
      """
      world, Hello
      """

  Scenario: Regex search/replace with a incorrect `--regex-flags`
    Given a WP install
    When I try `wp search-replace '(Hello)\s(world)' '$2, $1' --regex --regex-flags='kppr'`
    Then STDERR should be:
      """
      Error: The regex pattern '(Hello)\s(world)' with default delimiter 'chr(1)' and flags 'kppr' fails.
      preg_match(): Unknown modifier 'k'.
      """
    And the return code should be 1

  @require-mysql
  Scenario: Search and replace within theme mods
    Given a WP install
    And a setup-theme-mod.php file:
      """
      <?php
      set_theme_mod( 'header_image_data', (object) array( 'url' => 'https://subdomain.example.com/foo.jpg' ) );
      """
    And I run `wp eval-file setup-theme-mod.php`

    When I run `wp theme mod get header_image_data`
    Then STDOUT should contain:
      """
      https://subdomain.example.com/foo.jpg
      """

    When I run `wp search-replace subdomain.example.com example.com --no-recurse-objects`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 0            | PHP  |

    When I run `wp search-replace subdomain.example.com example.com`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 1            | PHP  |

    When I run `wp theme mod get header_image_data`
    Then STDOUT should contain:
      """
        url	https://example.com/foo.jpg
      """

  @require-mysql
  Scenario: Search and replace handles JSON-encoded URLs in post content
    Given a WP install

    When I run `wp post create --post_content='{"src":"http:\/\/example.com\/wp-content\/uploads\/fonts\/test.woff2","fontWeight":"400"}' --post_status=publish --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http:\/\/example.com
      """

    When I run `wp search-replace 'http://example.com' 'http://newdomain.com' wp_posts --include-columns=post_content`
    Then STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 1            | SQL  |

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http:\/\/newdomain.com
      """
    And STDOUT should not contain:
      """
      http:\/\/example.com
      """

    When I run `wp search-replace 'http://newdomain.com' 'http://example.com' wp_posts --include-columns=post_content --precise`
    Then STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 1            | PHP  |

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      http:\/\/example.com
      """

  @require-mysql
  Scenario: Search and replace with quoted strings
    Given a WP install

    When I run `wp post create --post_content='<a href="https://apple.com">Apple</a>' --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      <a href="https://apple.com">Apple</a>
      """

    When I run `wp search-replace '<a href="https://apple.com">Apple</a>' '<a href="https://google.com">Google</a>' --dry-run`
    Then STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 1            | SQL  |

    When I run `wp search-replace '<a href="https://apple.com">Apple</a>' '<a href="https://google.com">Google</a>'`
    Then STDOUT should be a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 1            | SQL  |

    When I run `wp search-replace '<a href="https://google.com">Google</a>' '<a href="https://apple.com">Apple</a>' --dry-run`
    Then STDOUT should contain:
      """
      1 replacement to be made.
      """

    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      <a href="https://google.com">Google</a>
      """

  Scenario: Search and replace with the same terms
    Given a WP install

    When I try `wp search-replace foo foo`
    Then STDERR should be:
      """
      Warning: Replacement value 'foo' is identical to search value 'foo'. Skipping operation.
      """
    And STDOUT should be empty
    And the return code should be 0

  @require-mysql
  Scenario: Search and replace a table that has a multi-column primary key
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_multicol ( "id" bigint(20) NOT NULL AUTO_INCREMENT,"name" varchar(60) NOT NULL,"value" text NOT NULL,PRIMARY KEY ("id","name"),UNIQUE KEY "name" ("name") ) ENGINE=InnoDB DEFAULT CHARSET=utf8 "`
    And I run `wp db query "INSERT INTO wp_multicol VALUES (1, 'foo',  'bar')"`
    And I run `wp db query "INSERT INTO wp_multicol VALUES (2, 'bar',  'foo')"`

    When I run `wp search-replace bar replaced wp_multicol --all-tables`
    Then STDOUT should be a table containing rows:
      | Table       | Column | Replacements | Type |
      | wp_multicol | name   | 1            | SQL  |
      | wp_multicol | value  | 1            | SQL  |

  # Skip on 5.0 for now due to difficulties introduced by https://core.trac.wordpress.org/changeset/42981
  @less-than-wp-5.0
  Scenario Outline: Large guid search/replace where replacement contains search (or not)
    Given a WP install
    And I run `wp option get siteurl`
    And save STDOUT as {SITEURL}
    And I run `wp site empty --yes`
    And I run `wp post generate --count=20`

    When I run `wp search-replace <flags> {SITEURL} <replacement>`
    Then STDOUT should be a table containing rows:
      | Table    | Column | Replacements | Type |
      | wp_posts | guid   | 20           | SQL  |

    Examples:
      | replacement           | flags     |
      | {SITEURL}/subdir      |           |
      | https://newdomain.com |           |
      | https://newdomain.com | --dry-run |

  @require-mysql
  Scenario Outline: Choose replacement method (PHP or MySQL/MariaDB) given proper flags or data.
    Given a WP install
    And I run `wp option get siteurl`
    And save STDOUT as {SITEURL}
    When I run `wp search-replace <flags> {SITEURL} https://wordpress.org`

    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type       |
      | wp_options | option_value | 2            | <serial>   |
      | wp_posts   | post_title   | 0            | <noserial> |

    Examples:
      | flags     | serial | noserial |
      |           | PHP    | SQL      |
      | --precise | PHP    | PHP      |

  @require-mysql
  Scenario Outline: Ensure search and replace uses PHP (precise) mode when serialized data is found
    Given a WP install
    And I run `wp post create --post_content='<input>' --porcelain`
    And save STDOUT as {CONTROLPOST}
    And I run `wp search-replace --precise foo bar`
    And I run `wp post get {CONTROLPOST} --field=content`
    And save STDOUT as {CONTROL}
    And I run `wp post create --post_content='<input>' --porcelain`
    And save STDOUT as {TESTPOST}
    And I run `wp search-replace foo bar`

    When I run `wp post get {TESTPOST} --field=content`
    Then STDOUT should be:
      """
      {CONTROL}
      """

    Examples:
      | input                                 |
      | a:1:{s:3:"bar";s:3:"foo";}            |
      | O:8:"stdClass":1:{s:1:"a";s:3:"foo";} |

  @require-mysql
  Scenario: Search replace with a regex flag
    Given a WP install

    When I run `wp search-replace 'EXAMPLE.com' 'BAXAMPLE.com' wp_options --regex`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 0            | PHP  |

    When I run `wp option get home`
    Then STDOUT should be:
      """
      https://example.com
      """

    When I run `wp search-replace 'EXAMPLE.com' 'BAXAMPLE.com' wp_options --regex --regex-flags=i`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 5            | PHP  |

    When I run `wp option get home`
    Then STDOUT should be:
      """
      https://BAXAMPLE.com
      """

  @require-mysql
  Scenario: Search replace with a regex delimiter
    Given a WP install

    When I run `wp search-replace 'HTTPS://EXAMPLE.COM' 'https://example.jp/' wp_options --regex --regex-flags=i --regex-delimiter='#'`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 2            | PHP  |

    When I run `wp option get home`
    Then STDOUT should be:
      """
      https://example.jp
      """

    When I run `wp search-replace 'https://example.jp/' 'https://example.com/' wp_options --regex-delimiter='/'`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 2            | PHP  |

    When I run `wp option get home`
    Then STDOUT should be:
      """
      https://example.com
      """

    # NOTE: The preg_match() error message is a substring of the actual message that matches across supported PHP versions.
    # In PHP 8.2, the error message changed from
    #   "preg_match(): Delimiter must not be alphanumeric or backslash."
    # to
    #   "preg_match(): Delimiter must not be alphanumeric, backslash, or NUL"
    When I try `wp search-replace 'HTTPS://EXAMPLE.COM' 'https://example.jp/' wp_options --regex --regex-flags=i --regex-delimiter='1'`
    Then STDERR should contain:
      """
      Error: The regex '1HTTPS://EXAMPLE.COM1i' fails.
      preg_match(): Delimiter must not be alphanumeric
      """
    And the return code should be 1

    When I try `wp search-replace 'regex error)' '' --regex`
    Then STDERR should contain:
      """
      Error: The regex pattern 'regex error)' with default delimiter 'chr(1)' and no flags fails.
      """
    And STDERR should contain:
      """
      preg_match(): Compilation failed:
      """
    And STDERR should match /preg_match\(\): Compilation failed: unmatched (closing parenthesis|parentheses) at offset [0-9]+\.?/
    And the return code should be 1

    When I try `wp search-replace 'regex error)' '' --regex --regex-flags=u`
    Then STDERR should contain:
      """
      Error: The regex pattern 'regex error)' with default delimiter 'chr(1)' and flags 'u' fails.
      """
    And STDERR should contain:
      """
      preg_match(): Compilation failed:
      """
    And STDERR should match /preg_match\(\): Compilation failed: unmatched (closing parenthesis|parentheses) at offset [0-9]+\.?/
    And the return code should be 1

    When I try `wp search-replace 'regex error)' '' --regex --regex-delimiter=/`
    Then STDERR should contain:
      """
      Error: The regex '/regex error)/' fails.
      """
    And STDERR should contain:
      """
      preg_match(): Compilation failed:
      """
    And STDERR should match /preg_match\(\): Compilation failed: unmatched (closing parenthesis|parentheses) at offset [0-9]+\.?/
    And the return code should be 1

    When I try `wp search-replace 'regex error)' '' --regex --regex-delimiter=/ --regex-flags=u`
    Then STDERR should contain:
      """
      Error: The regex '/regex error)/u' fails.
      """
    And STDERR should contain:
      """
      preg_match(): Compilation failed:
      """
    And STDERR should match /preg_match\(\): Compilation failed: unmatched (closing parenthesis|parentheses) at offset [0-9]+\.?/
    And the return code should be 1

  @require-mysql
  Scenario: Formatting as count-only
    Given a WP install
    And I run `wp option set foo 'ALPHA.example.com'`

    # --quite should suppress --format=count
    When I run `wp search-replace 'ALPHA.example.com' 'BETA.example.com' --quiet --format=count`
    Then STDOUT should be empty

    # --format=count should suppress --verbose
    When I run `wp search-replace 'BETA.example.com' 'ALPHA.example.com' --format=count --verbose`
    Then STDOUT should be:
      """
      1
      """

    # The normal command
    When I run `wp search-replace 'ALPHA.example.com' 'BETA.example.com' --format=count`
    Then STDOUT should be:
      """
      1
      """

    # Lets just make sure that zero works, too.
    When I run `wp search-replace 'DELTA.example.com' 'ALPHA.example.com' --format=count`
    Then STDOUT should be:
      """
      0
      """

  @require-mysql
  Scenario: Search / replace should cater for field/table names that use reserved words or unusual characters
    Given a WP install
    And a esc_sql_ident.sql file:
      """
      CREATE TABLE `TABLE` (`KEY` INT(11) UNSIGNED NOT NULL AUTO_INCREMENT, `VALUES` TEXT, `back``tick` TEXT, `single'double"quote` TEXT, PRIMARY KEY (`KEY`) );
      INSERT INTO `TABLE` (`VALUES`, `back``tick`, `single'double"quote`) VALUES ('v"vvvv_v1', 'v"vvvv_v1', 'v"vvvv_v1' );
      INSERT INTO `TABLE` (`VALUES`, `back``tick`, `single'double"quote`) VALUES ('v"vvvv_v2', 'v"vvvv_v2', 'v"vvvv_v2' );
      """

    When I run `wp db query "SOURCE esc_sql_ident.sql;"`
    Then STDERR should be empty

    When I run `wp search-replace 'v"vvvv_v' 'w"wwww_w' TABLE --format=count --all-tables`
    Then STDOUT should be:
      """
      6
      """
    And STDERR should be empty

    # Regex uses wpdb::update() which can't handle backticks in field names so avoid `back``tick` column.
    When I run `wp search-replace 'w"wwww_w' 'v"vvvv_v' TABLE --regex --include-columns='VALUES,single'\''double"quote' --format=count --all-tables`
    Then STDOUT should be:
      """
      4
      """
    And STDERR should be empty

  @require-mysql @suppress_report__only_changes
  Scenario: Suppress report or only report changes
    Given a WP install

    When I run `wp option set foo baz`
    And I run `wp option get foo`
    Then STDOUT should be:
      """
      baz
      """

    When I run `wp post create --post_title=baz --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp post meta add {POST_ID} foo baz`
    Then STDOUT should not be empty

    When I run `wp search-replace baz baz1`
    Then STDOUT should contain:
      """
      Success: Made 3 replacements.
      """
    And STDOUT should be a table containing rows:
      | Table          | Column       | Replacements | Type |
      | wp_commentmeta | meta_key     | 0            | SQL  |
      | wp_options     | option_value | 1            | PHP  |
      | wp_postmeta    | meta_value   | 1            | SQL  |
      | wp_posts       | post_title   | 1            | SQL  |
      | wp_users       | display_name | 0            | SQL  |
    And STDERR should be empty

    When I run `wp search-replace baz1 baz2 --report`
    Then STDOUT should contain:
      """
      Success: Made 3 replacements.
      """
    And STDOUT should be a table containing rows:
      | Table          | Column       | Replacements | Type |
      | wp_commentmeta | meta_key     | 0            | SQL  |
      | wp_options     | option_value | 1            | PHP  |
      | wp_postmeta    | meta_value   | 1            | SQL  |
      | wp_posts       | post_title   | 1            | SQL  |
      | wp_users       | display_name | 0            | SQL  |
    And STDERR should be empty

    When I run `wp search-replace baz2 baz3 --no-report`
    Then STDOUT should contain:
      """
      Success: Made 3 replacements.
      """
    And STDOUT should not contain:
      """
      Table	Column	Replacements	Type
      """
    And STDOUT should not contain:
      """
      wp_commentmeta	meta_key	0	SQL
      """
    And STDOUT should not contain:
      """
      wp_options	option_value	1	PHP
      """
    And STDERR should be empty

    When I run `wp search-replace baz3 baz4 --no-report-changed-only`
    Then STDOUT should contain:
      """
      Success: Made 3 replacements.
      """
    And STDOUT should be a table containing rows:
      | Table          | Column       | Replacements | Type |
      | wp_commentmeta | meta_key     | 0            | SQL  |
      | wp_options     | option_value | 1            | PHP  |
      | wp_postmeta    | meta_value   | 1            | SQL  |
      | wp_posts       | post_title   | 1            | SQL  |
      | wp_users       | display_name | 0            | SQL  |
    And STDERR should be empty

    When I run `wp search-replace baz4 baz5 --report-changed-only`
    Then STDOUT should contain:
      """
      Success: Made 3 replacements.
      """
    And STDOUT should end with a table containing rows:
      | Table       | Column       | Replacements | Type |
      | wp_options  | option_value | 1            | PHP  |
      | wp_postmeta | meta_value   | 1            | SQL  |
      | wp_posts    | post_title   | 1            | SQL  |
    And STDOUT should not contain:
      """
      wp_commentmeta	meta_key	0	SQL
      """
    And STDOUT should not contain:
      """
      wp_users	display_name	0	SQL
      """
    And STDERR should be empty

    When I run `wp search-replace nobaz1 baz6 --report-changed-only`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """
    And STDOUT should not contain:
      """
      Table	Column	Replacements	Type
      """
    And STDERR should be empty

  @require-mysql @no_table__no_primary_key
  Scenario: Deal with non-existent table and table with no primary keys
    Given a WP install

    When I try `wp search-replace foo bar no_such_table --all-tables`
    Then STDOUT should be empty
    And STDERR should be:
      """
      Error: Couldn't find any tables matching: no_such_table
      """
    And the return code should be 1

    When I run `wp db query "CREATE TABLE no_key ( awesome_stuff TEXT );"`
    And I run `wp search-replace foo bar no_key --all-tables`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """
    And STDOUT should end with a table containing rows:
      | Table  | Column | Replacements | Type |
      | no_key |        | skipped      |      |
    And STDERR should be empty

    When I run `wp search-replace foo bar no_key --report-changed-only --all-tables`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """
    And STDOUT should not contain:
      """
      | Table  | Column | Replacements | Type |
      | no_key |        | skipped      |      |
      """
    And STDERR should be empty

    When I try `wp search-replace foo bar no_key --no-report --all-tables`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """
    And STDOUT should not contain:
      """
      Table	Column	Replacements	Type
      """
    And STDERR should be:
      """
      Warning: No primary keys for table 'no_key'.
      """
    And the return code should be 0

  @require-mysql
  Scenario: Search / replace is case sensitive
    Given a WP install
    When I run `wp post create --post_title='Case Sensitive' --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace sensitive insensitive`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """
    And STDERR should be empty

    When I run `wp search-replace sensitive insensitive --dry-run`
    Then STDOUT should contain:
      """
      Success: 0 replacements to be made.
      """
    And STDERR should be empty

    When I run `wp search-replace Sensitive insensitive --dry-run`
    Then STDOUT should contain:
      """
      Success: 1 replacement to be made.
      """
    And STDERR should be empty

    When I run `wp search-replace Sensitive insensitive`
    Then STDOUT should contain:
      """
      Success: Made 1 replacement.
      """
    And STDERR should be empty

  @require-mysql
  Scenario: Logging with simple replace
    Given a WP install

    When I run `wp post create --post_title='Title_baz__baz_' --post_content='Content_baz_12345678901234567890_baz_12345678901234567890' --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace '_baz_' '_' wp_posts --dry-run --log --before_context=10 --after_context=10`
    Then STDOUT should contain:
      """
      Success: 2 replacements to be made.
      """
    And STDOUT should end with a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 1            | SQL  |
      | wp_posts | post_title   | 1            | SQL  |

    And STDOUT should contain:
      """
      wp_posts.post_content:{POST_ID}
      < Content_baz_1234567890 [...] 1234567890_baz_1234567890
      > Content_1234567890 [...] 1234567890_1234567890
      """
    And STDOUT should contain:
      """
      wp_posts.post_title:{POST_ID}
      < Title_baz__baz_
      > Title__
      """
    And STDERR should be empty

    When I run `wp search-replace '_baz_' '' wp_posts --dry-run --log=replace.log`
    Then STDOUT should contain:
      """
      Success: 2 replacements to be made.
      """
    And STDOUT should not contain:
      """
      < Content
      """
    And the replace.log file should contain:
      """
      wp_posts.post_content:{POST_ID}
      < Content_baz_12345678901234567890_baz_12345678901234567890
      > Content1234567890123456789012345678901234567890
      """
    And the replace.log file should contain:
      """
      wp_posts.post_title:{POST_ID}
      < Title_baz__baz_
      > Title
      """
    And STDERR should be empty

    # kana with diacritic and decomposed "a" + umlaut.
    When I run `wp search-replace '_baz_' '_バäz_' wp_posts --log=- --before_context=10 --after_context=20`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """
    And STDOUT should contain:
      """
      wp_posts.post_content:{POST_ID}
      < Content_baz_12345678901234567890 [...] 1234567890_baz_12345678901234567890
      > Content_バäz_12345678901234567890 [...] 1234567890_バäz_12345678901234567890
      """
    And STDERR should be empty

    # Testing UTF-8 context
    When I run `wp search-replace 'z_' 'zzzz_' wp_posts --log --before_context=2 --after_context=1`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """
    And STDOUT should contain:
      """
      wp_posts.post_content:{POST_ID}
      < バäz_1 [...] バäz_1
      > バäzzzz_1 [...] バäzzzz_1
      """
    And STDERR should be empty

    When I run `wp option set foobar '_bar1_ _bar1_12345678901234567890123456789012345678901234567890_bar1_ _bar1_1234567890123456789012345678901234567890'`
    And I run `wp search-replace '_bar1_' '_baz1_' wp_options --log`
    Then STDOUT should contain:
      """
      < _bar1_ _bar1_1234567890123456789012345678901234567890 [...] 1234567890123456789012345678901234567890_bar1_ _bar1_1234567890123456789012345678901234567890
      > _baz1_ _baz1_1234567890123456789012345678901234567890 [...] 1234567890123456789012345678901234567890_baz1_ _baz1_1234567890123456789012345678901234567890
      """
    And STDERR should be empty

    When I run `wp option get foobar`
    Then STDOUT should be:
      """
      _baz1_ _baz1_12345678901234567890123456789012345678901234567890_baz1_ _baz1_1234567890123456789012345678901234567890
      """

    When I run `wp search-replace '_baz1_' '_bar1_' wp_options --log --before_context=10 --after_context=10`
    Then STDOUT should contain:
      """
      < _baz1_ _baz1_1234567890 [...] 1234567890_baz1_ _baz1_1234567890
      > _bar1_ _bar1_1234567890 [...] 1234567890_bar1_ _bar1_1234567890
      """
    And STDERR should be empty

    When I run `wp option set foobar2 '12345678901234567890_bar2_1234567890_bar2_ _bar2_ _bar2_'`
    And I run `wp search-replace '_bar2_' '_baz2baz2_' wp_options --log --before_context=10 --after_context=10`
    Then STDOUT should contain:
      """
      < 1234567890_bar2_1234567890 [...] 1234567890_bar2_ _bar2_ _bar2_
      > 1234567890_baz2baz2_1234567890 [...] 1234567890_baz2baz2_ _baz2baz2_ _baz2baz2_
      """
    And STDERR should be empty

    When I run `wp option get foobar2`
    Then STDOUT should be:
      """
      12345678901234567890_baz2baz2_1234567890_baz2baz2_ _baz2baz2_ _baz2baz2_
      """

    When I run `wp search-replace '_baz2baz2_' '_barz2_' wp_options --log  --before_context=10 --after_context=4`
    Then STDOUT should contain:
      """
      < 1234567890_baz2baz2_1234 [...] 1234567890_baz2baz2_ _baz2baz2_ _baz2baz2_
      > 1234567890_barz2_1234 [...] 1234567890_barz2_ _barz2_ _barz2_
      """
    And STDERR should be empty

    When I run `wp option set foobar3 '_bar3 _bar3 _bar3 _bar3'`
    And I run `wp search-replace '_bar3' 'baz3' wp_options --log`
    Then STDOUT should contain:
      """
      < _bar3 _bar3 _bar3 _bar3
      > baz3 baz3 baz3 baz3
      """
    And STDERR should be empty

    When I run `wp option get foobar3`
    Then STDOUT should be:
      """
      baz3 baz3 baz3 baz3
      """

    When I run `wp search-replace 'baz3' 'baz\3' wp_options --dry-run --log`
    Then STDOUT should contain:
      """
      < baz3 baz3 baz3 baz3
      > baz\3 baz\3 baz\3 baz\3
      """
    And STDERR should be empty

  # See https://github.com/wp-cli/search-replace-command/issues/190
  # SQLite: regex backreference replacement produces different results due to
  # LIKE case-sensitivity differences. Requires further investigation.
  @skip-sqlite
  Scenario: Logging with regex replace
    Given a WP install

    When I run `wp post create --post_title='Title_baz__boz_' --post_content='Content_baz_1234567890_bez_1234567890_biz_1234567890_boz_1234567890_buz_' --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace '_b[aeiou]z_' '_bz_' wp_posts --regex --dry-run --log  --before_context=11 --after_context=11`
    Then STDOUT should contain:
      """
      Success: 2 replacements to be made.
      """
    And STDOUT should end with a table containing rows:
      | Table    | Column       | Replacements | Type |
      | wp_posts | post_content | 1            | PHP  |
      | wp_posts | post_title   | 1            | PHP  |

    And STDOUT should contain:
      """
      wp_posts.post_content:{POST_ID}
      < Content_baz_1234567890_bez_1234567890_biz_1234567890_boz_1234567890_buz_
      > Content_bz_1234567890_bz_1234567890_bz_1234567890_bz_1234567890_bz_
      """
    And STDOUT should contain:
      """
      wp_posts.post_title:{POST_ID}
      < Title_baz__boz_
      > Title_bz__bz_
      """
    And STDERR should be empty

    When I run `wp search-replace '_b([aeiou])z_' '_$1b\\1z_\0' wp_posts --regex --log --before_context=11 --after_context=11`
    Then STDOUT should contain:
      """
      Success: Made 2 replacements.
      """

    And STDOUT should contain:
      """
      wp_posts.post_content:{POST_ID}
      < Content_baz_1234567890_bez_1234567890_biz_1234567890_boz_1234567890_buz_
      > Content_ab\1z__baz_1234567890_eb\1z__bez_1234567890_ib\1z__biz_1234567890_ob\1z__boz_1234567890_ub\1z__buz_
      """
    And STDOUT should contain:
      """
      wp_posts.post_title:{POST_ID}
      < Title_baz__boz_
      > Title_ab\1z__baz__ob\1z__boz_
      """
    And STDERR should be empty

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      Title_ab\1z__baz__ob\1z__boz_
      """

    When I run `wp post get {POST_ID} --field=content`
    Then STDOUT should be:
      """
      Content_ab\1z__baz_1234567890_eb\1z__bez_1234567890_ib\1z__biz_1234567890_ob\1z__boz_1234567890_ub\1z__buz_
      """

  @require-mysql
  Scenario: Logging with prefixes and custom colors
    Given a WP install
    And I run `wp option set blogdescription 'Just another WordPress site'`

    When I run `WP_CLI_SEARCH_REPLACE_LOG_PREFIXES='- ,+ ' wp search-replace Just Yet --dry-run --log`
    Then STDOUT should contain:
      """
      - Just another WordPress site
      + Yet another WordPress site
      """
    And STDERR should be empty

    When I run `WP_CLI_SEARCH_REPLACE_LOG_PREFIXES=',' wp search-replace Just Yet --dry-run --log`
    Then STDOUT should not contain:
      """
      < Just
      """
    And STDOUT should contain:
      """
      Just
      """
    And STDOUT should not contain:
      """
      > Yet
      """
    And STDOUT should contain:
      """
      Yet
      """
    And STDERR should be empty

    When I run `SHELL_PIPE=0 wp search-replace WordPress WP --dry-run --log`
    Then STDOUT should strictly contain:
      """
      [34;1mwp_options.option_value:
      """
    And STDOUT should strictly contain:
      """
      [31;1m< [0mJust another [31;1mWordPress[0m site
      [32;1m> [0mJust another [32;1mWP[0m site
      """
    And STDERR should be empty

    When I run `SHELL_PIPE=0 WP_CLI_SEARCH_REPLACE_LOG_COLORS='%b,%r,%g' wp search-replace WordPress WP --dry-run --log`
    Then STDOUT should strictly contain:
      """
      [34mwp_options.option_value:
      """
    And STDOUT should strictly contain:
      """
      [31m< [0mJust another [31mWordPress[0m site
      [32m> [0mJust another [32mWP[0m site
      """
    And STDERR should be empty

    When I run `SHELL_PIPE=0 WP_CLI_SEARCH_REPLACE_LOG_COLORS='%b,%r,%g' wp search-replace WordPress WP --dry-run --log=replace.log`
    Then STDOUT should not contain:
      """
      wp_options.option_value
      """
    And the replace.log file should strictly contain:
      """
      [34mwp_options.option_value:
      """
    And the replace.log file should strictly contain:
      """
      [31m< [0mJust another [31mWordPress[0m site
      [32m> [0mJust another [32mWP[0m site
      """
    And STDERR should be empty

    When I run `SHELL_PIPE=0 wp search-replace WordPress WP --dry-run --log=replace.log`
    Then STDOUT should not contain:
      """
      wp_options.option_value
      """
    And the replace.log file should contain:
      """
      wp_options.option_value:
      """
    And the replace.log file should contain:
      """
      < Just another WordPress site
      > Just another WP site
      """
    And STDERR should be empty

    When I run `SHELL_PIPE=0 WP_CLI_SEARCH_REPLACE_LOG_COLORS=',,' wp search-replace WordPress WP --dry-run --log`
    Then STDOUT should contain:
      """
      wp_options.option_value:
      """
    And STDOUT should contain:
      """
      < Just another WordPress site
      > Just another WP site
      """
    And STDERR should be empty

  # Regression test for https://github.com/wp-cli/search-replace-command/issues/58
  @require-mysql
  Scenario: The parameters --regex and --all-tables-with-prefix produce valid SQL
    Given a WP install
    And a test_db.sql file:
      """
      CREATE TABLE `wp_123_test` (
      `name` varchar(50),
      `value` varchar(5000),
      `created_at` datetime NOT NULL,
      `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`name`)
      ) ENGINE=InnoDB;
      INSERT INTO `wp_123_test` VALUES ('test_val','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');
      INSERT INTO `wp_123_test` VALUES ('123.','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');
      INSERT INTO `wp_123_test` VALUES ('quote\'quote','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');
      INSERT INTO `wp_123_test` VALUES ('0','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');
      INSERT INTO `wp_123_test` VALUES ('','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');
      INSERT INTO `wp_123_test` VALUES ('18446744073709551616','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');
      INSERT INTO `wp_123_test` VALUES ('-18446744073709551615','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');
      INSERT INTO `wp_123_test` VALUES ('123456789012345678801234567890','wp_123_test_value_X','2016-11-15 14:41:33','2016-11-15 21:41:33');

      CREATE TABLE `wp_123_test2` (`bigint_unsigned_key` BIGINT UNSIGNED NOT NULL, `value` VARCHAR(255), PRIMARY KEY (`bigint_unsigned_key`) );
      INSERT INTO `wp_123_test2` VALUES ('18446744073709551615','wp_123_test2_value_X');

      CREATE TABLE `wp_123_test3` (`bigint_signed_key` BIGINT SIGNED NOT NULL, `value` VARCHAR(255), PRIMARY KEY (`bigint_signed_key`) );
      INSERT INTO `wp_123_test3` VALUES ('-9223372036854775808','wp_123_test3_value_X');
      """
    And I run `wp db query "SOURCE test_db.sql;"`

    When I run `wp search-replace --dry-run --regex 'mytestdomain.com\/' 'mytestdomain2.com/' --all-tables-with-prefix --skip-columns=guid,domain`
    Then STDOUT should contain:
      """
      Success: 0 replacements to be made.
      """

    When I run `wp search-replace --dry-run --regex 'wp_123_test_value_X' 'wp_123_test_value_Y' --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      Success: 8 replacements to be made.
      """

    When I run `wp search-replace --dry-run --regex 'wp_123_test2_value_X' 'wp_123_test2_value_Y' --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      Success: 1 replacement to be made.
      """

    When I run `wp search-replace --dry-run --regex 'wp_123_test3_value_X' 'wp_123_test3_value_Y' --all-tables-with-prefix`
    Then STDOUT should contain:
      """
      Success: 1 replacement to be made.
      """

  # Regression test for https://github.com/wp-cli/search-replace-command/issues/68
  @require-mysql
  Scenario: Incomplete classes are handled gracefully during (un)serialization

    Given a WP install
    And I run `wp option add cereal_isation 'a:1:{i:0;O:10:"CornFlakes":0:{}}'`

    When I try `wp search-replace CornFlakes Smacks`
    Then STDERR should contain:
      """
      Warning: Skipping an uninitialized class "CornFlakes", replacements might not be complete.
      """
    And STDOUT should contain:
      """
      Success: Made 0 replacements.
      """

    When I run `wp option get cereal_isation`
    Then STDOUT should contain:
      """
      a:1:{i:0;O:10:"CornFlakes":0:{}}
      """

  # `CaseInsensitiveDictionary` is from Requests 2.0, which was added in 6.2.
  @require-wp-6.2
  Scenario: Search-replace updates iterable dictionary objects without dynamic property deprecations

    Given a WP install
    And a search-replace-case-insensitive-dictionary.php file:
      """
      <?php
      WP_CLI::add_hook(
          'search_replace_unserialize_options',
          function () {
              return [ 'allowed_classes' => [ 'stdClass', 'WpOrg\Requests\Utility\CaseInsensitiveDictionary' ] ];
          }
      );
      $replacer = new \WP_CLI\SearchReplacer( 'old.example.com', 'new.example.com', true );
      echo $replacer->run(
          serialize(
              new \WpOrg\Requests\Utility\CaseInsensitiveDictionary(
                  [
                      'date' => 'https://old.example.com/feed',
                  ]
              )
          )
      );
      """

    When I run `wp eval-file search-replace-case-insensitive-dictionary.php`
    Then STDERR should be empty
    And STDOUT should contain:
      """
      https://new.example.com/feed
      """
    And STDOUT should not contain:
      """
      https://old.example.com/feed
      """

  @require-mysql
  Scenario: The search_replace_unserialize_options hook allows overriding allowed_classes for unserialize

    Given a WP install
    And I run `wp db query "INSERT INTO wp_options (option_name,option_value) VALUES ('cereal_isation','O:7:\"MyClass\":1:{s:3:\"foo\";s:13:\"cereal_marker\";}')"`
    And a hook.php file:
      """
      <?php
      class MyClass {
          public $foo = '';
      }
      WP_CLI::add_hook(
          'search_replace_unserialize_options',
          function () {
              return [ 'allowed_classes' => [ 'stdClass', 'MyClass' ] ];
          }
      );
      """

    When I try `wp search-replace cereal_marker cereal_replaced`
    Then STDERR should contain:
      """
      Warning: Skipping an uninitialized class "MyClass", replacements might not be complete.
      """
    And STDOUT should contain:
      """
      Success: Made 0 replacements.
      """

    When I run `wp --require=hook.php search-replace cereal_marker cereal_replaced`
    Then STDERR should be empty
    And STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

  @require-mysql
  Scenario: Warn and ignore type-hinted objects that have some error in deserialization

    Given a WP install
    And I run `wp db query "INSERT INTO wp_options (option_name,option_value) VALUES ('cereal_isation','O:13:\"mysqli_result\":5:{s:13:\"current_field\";N;s:11:\"field_count\";N;s:7:\"lengths\";N;s:8:\"num_rows\";N;s:4:\"type\";N;}')"`
    And I run `wp db query "INSERT INTO wp_options (option_name,option_value) VALUES ('cereal_isation_2','O:8:\"mysqli_result\":5:{s:13:\"current_field\";i:1;s:11:\"field_count\";i:2;s:7:\"lengths\";a:1:{i:0;s:4:\"blah\";}s:8:\"num_rows\";i:1;s:4:\"type\";i:2;}')"`

    When I try `wp search-replace mysqli_result stdClass`
    Then STDERR should contain:
      """
      Warning: Skipping an uninitialized class "mysqli_result", replacements might not be complete.
      """
    And STDOUT should contain:
      """
      Success: Made 1 replacement.
      """

  # See https://github.com/wp-cli/search-replace-command/issues/190
  Scenario: Regex search/replace with `--regex-limit=1` option
    Given a WP install
    And I run `wp post create --post_content="I have a pen, I have an apple. Pen, pine-apple, apple-pen."`

    When I run `wp search-replace --regex "ap{2}le" "orange" --regex-limit=1 --log`
    Then STDOUT should contain:
      """
      I have a pen, I have an orange. Pen, pine-apple, apple-pen.
      """

  # See https://github.com/wp-cli/search-replace-command/issues/190
  Scenario: Regex search/replace with `--regex-limit=2` option
    Given a WP install
    And I run `wp post create --post_content="I have a pen, I have an apple. Pen, pine-apple, apple-pen."`

    When I run `wp search-replace --regex "ap{2}le" "orange" --regex-limit=2 --log`
    Then STDOUT should contain:
      """
      I have a pen, I have an orange. Pen, pine-orange, apple-pen.
      """

  # See https://github.com/wp-cli/search-replace-command/issues/190
  Scenario: Regex search/replace with incorrect or default `--regex-limit`
    Given a WP install
    When I try `wp search-replace '(Hello)\s(world)' '$2, $1' --regex --regex-limit=asdf`
    Then STDERR should be:
      """
      Error: `--regex-limit` expects a non-zero positive integer or -1.
      """
    When I try `wp search-replace '(Hello)\s(world)' '$2, $1' --regex --regex-limit=0`
    Then STDERR should be:
      """
      Error: `--regex-limit` expects a non-zero positive integer or -1.
      """
    When I try `wp search-replace '(Hello)\s(world)' '$2, $1' --regex --regex-limit=-2`
    Then STDERR should be:
      """
      Error: `--regex-limit` expects a non-zero positive integer or -1.
      """
    When I run `wp search-replace '(Hello)\s(world)' '$2, $1' --regex --regex-limit=-1`
    Then STDOUT should contain:
      """
      Success:
      """

  @require-mysql
  Scenario: Chunking a precise search and replace works without skipping lines
    Given a WP install
    And a create_sql_file.sh file:
      """
      #!/bin/bash
      echo "CREATE TABLE \`wp_123_test\` (\`key\` INT(5) UNSIGNED NOT NULL AUTO_INCREMENT, \`text\` TEXT, PRIMARY KEY (\`key\`) );" > test_db.sql
      echo "INSERT INTO \`wp_123_test\` (\`text\`) VALUES" >> test_db.sql
      index=1
      while [[ $index -le 199 ]];
      do
      echo "('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc')," >> test_db.sql
      index=`expr $index + 1`
      done
      echo "('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc');" >> test_db.sql
      echo "CREATE TABLE \`wp_123_test_multikey\` (\`key1\` INT(5) UNSIGNED NOT NULL AUTO_INCREMENT, \`key2\` INT(5) UNSIGNED NOT NULL, \`key3\` INT(5) UNSIGNED NOT NULL, \`text\` TEXT, PRIMARY KEY (\`key1\`,\`key2\`,\`key3\`) );" >> test_db.sql
      echo "INSERT INTO \`wp_123_test_multikey\` (\`key2\`,\`key3\`,\`text\`) VALUES" >> test_db.sql
      index=1
      while [[ $index -le 204 ]];
      do
      echo "(0,0,'abc'),(1,1,'abc'),(2,2,'abc'),(3,3,'abc'),(4,4,'abc'),(5,0,'abc'),(6,1,'abc'),(7,2,'abc'),(8,3,'abc'),(9,4,'abc')," >> test_db.sql
      index=`expr $index + 1`
      done
      echo "(0,0,'abc'),(1,1,'abc'),(2,2,'abc'),(3,3,'abc'),(4,4,'abc'),(5,0,'abc'),(6,1,'abc'),(7,2,'abc'),(8,3,'abc'),(9,4,'abc');" >> test_db.sql
      """
    And I run `bash create_sql_file.sh`
    And I run `wp db query "SOURCE test_db.sql;"`

    When I run `wp search-replace --dry-run 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --precise`
    Then STDOUT should contain:
      """
      Success: 4050 replacements to be made.
      """

    When I run `wp search-replace 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --precise`
    Then STDOUT should contain:
      """
      Success: Made 4050 replacements.
      """

    When I run `wp search-replace --dry-run 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --precise`
    Then STDOUT should contain:
      """
      Success: 0 replacements to be made.
      """

    When I run `wp search-replace 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --precise`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """

  @require-mysql
  Scenario: Chunking a regex search and replace works without skipping lines
    Given a WP install
    And a create_sql_file.sh file:
      """
      #!/bin/bash
      echo "CREATE TABLE \`wp_123_test\` (\`key\` INT(5) UNSIGNED NOT NULL AUTO_INCREMENT, \`text\` TEXT, PRIMARY KEY (\`key\`) );" > test_db.sql
      echo "INSERT INTO \`wp_123_test\` (\`text\`) VALUES" >> test_db.sql
      index=1
      while [[ $index -le 199 ]];
      do
      echo "('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc')," >> test_db.sql
      index=`expr $index + 1`
      done
      echo "('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc'),('abc');" >> test_db.sql
      echo "CREATE TABLE \`wp_123_test_multikey\` (\`key1\` INT(5) UNSIGNED NOT NULL AUTO_INCREMENT, \`key2\` INT(5) UNSIGNED NOT NULL, \`key3\` INT(5) UNSIGNED NOT NULL, \`text\` TEXT, PRIMARY KEY (\`key1\`,\`key2\`,\`key3\`) );" >> test_db.sql
      echo "INSERT INTO \`wp_123_test_multikey\` (\`key2\`,\`key3\`,\`text\`) VALUES" >> test_db.sql
      index=1
      while [[ $index -le 204 ]];
      do
      echo "(0,0,'abc'),(1,1,'abc'),(2,2,'abc'),(3,3,'abc'),(4,4,'abc'),(5,0,'abc'),(6,1,'abc'),(7,2,'abc'),(8,3,'abc'),(9,4,'abc')," >> test_db.sql
      index=`expr $index + 1`
      done
      echo "(0,0,'abc'),(1,1,'abc'),(2,2,'abc'),(3,3,'abc'),(4,4,'abc'),(5,0,'abc'),(6,1,'abc'),(7,2,'abc'),(8,3,'abc'),(9,4,'abc');" >> test_db.sql
      """
    And I run `bash create_sql_file.sh`
    And I run `wp db query "SOURCE test_db.sql;"`

    When I run `wp search-replace --dry-run 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --regex`
    Then STDOUT should contain:
      """
      Success: 4050 replacements to be made.
      """

    When I run `wp search-replace 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --regex`
    Then STDOUT should contain:
      """
      Success: Made 4050 replacements.
      """

    When I run `wp search-replace --dry-run 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --regex`
    Then STDOUT should contain:
      """
      Success: 0 replacements to be made.
      """

    When I run `wp search-replace 'abc' 'def' --all-tables-with-prefix --skip-columns=guid,domain --regex`
    Then STDOUT should contain:
      """
      Success: Made 0 replacements.
      """

  @require-mysql
  Scenario: Search/replace strings starting with hyphens using --old and --new flags
    Given a WP install
    And I run `wp post create --post_title="Test Post" --post_content="This is --old-content and more text" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --old='--old-content' --new='--new-content'`
    Then STDOUT should contain:
      """
      wp_posts
      """
    And the return code should be 0

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      --new-content
      """
    And STDOUT should not contain:
      """
      --old-content
      """

  @require-mysql
  Scenario: Error when neither positional args nor flags provided
    Given a WP install

    When I try `wp search-replace`
    Then STDERR should contain:
      """
      Please provide both <old> and <new> arguments
      """
    And STDERR should contain:
      """
      --old
      """
    And STDERR should contain:
      """
      --new
      """
    And the return code should be 1

  @require-mysql
  Scenario: Error when only --old flag provided without --new
    Given a WP install

    When I try `wp search-replace --old='test-value'`
    Then STDERR should contain:
      """
      Please provide the <new> argument
      """
    And the return code should be 1

  @require-mysql
  Scenario: Error when only --new flag provided without --old
    Given a WP install

    When I try `wp search-replace --new='test-value'`
    Then STDERR should contain:
      """
      Please provide the <old> argument
      """
    And the return code should be 1

  @require-mysql
  Scenario: Error when both flags and positional arguments provided
    Given a WP install

    When I try `wp search-replace --old='flag-old' --new='flag-new' 'positional-arg'`
    Then STDERR should contain:
      """
      Cannot use both positional arguments and --old/--new flags
      """
    And the return code should be 1

  @require-mysql
  Scenario: Error when empty string provided via --old flag
    Given a WP install

    When I try `wp search-replace --old='' --new='replacement'`
    Then STDERR should contain:
      """
      Please provide the <old> argument
      """
    And the return code should be 1

  @require-mysql
  Scenario: No error when empty string provided via --new flag
    Given a WP install

    When I try `wp search-replace --old='search' --new=''`
    Then STDERR should not contain:
      """
      Please provide the <new> argument
      """

  @require-mysql
  Scenario: Search/replace string starting with single hyphen works with positional args
    Given a WP install
    And I run `wp post create --post_title="Test Post" --post_content="This is -single-hyphen content" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace '-single-hyphen' '-replaced-hyphen'`
    Then STDOUT should contain:
      """
      wp_posts
      """
    And the return code should be 0

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      -replaced-hyphen
      """
    And STDOUT should not contain:
      """
      -single-hyphen
      """

  @require-mysql
  Scenario: Allow mixing one flag with one positional argument
    Given a WP install
    And I run `wp post create --post_title="Test Post" --post_content="This is --old-content text" --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --old='--old-content' 'new-content'`
    Then STDOUT should contain:
      """
      wp_posts
      """
    And the return code should be 0

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should contain:
      """
      new-content
      """
    And STDOUT should not contain:
      """
      --old-content
      """


  @require-mysql
  Scenario: Warn when updating a table fails due to a database error
    Given a WP install
    And I run `wp db query "CREATE TABLE wp_readonly_test ( id int(11) unsigned NOT NULL AUTO_INCREMENT, data VARCHAR(191), PRIMARY KEY (id), UNIQUE KEY data (data) ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"`
    And I run `wp db query "INSERT INTO wp_readonly_test (data) VALUES ('old-value'), ('new-value');"`

    When I try `wp search-replace old-value new-value --all-tables-with-prefix`
    Then STDERR should contain:
      """
      Error updating column 'data' in table 'wp_readonly_test'
      """
    And STDERR should contain:
      """
      Duplicate entry
      """

  @require-mysql
  Scenario: Report types and counts are based on serialized data in the column
    Given a WP install
    And I run `wp option add sr_serialized_match '{"url":"https://match.example/x"}' --format=json`
    And I run `wp option add sr_plain_match 'see https://match.example/y'`
    And I run `wp post create --post_title='Has match.example in it' --post_content='Plain match.example content' --porcelain`
    And save STDOUT as {POST_ID}

    # option_value holds serialized data (the option above), so it is handled in PHP.
    # post_title has no serialized data, so it is handled in SQL. post_excerpt has no matches.
    When I run `wp search-replace match.example other.example --dry-run --include-columns=option_value,post_title,post_excerpt`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 2            | PHP  |
      | wp_posts   | post_title   | 1            | SQL  |
      | wp_posts   | post_excerpt | 0            | SQL  |

    # A column with serialized data is reported as PHP even when none of it matches.
    When I run `wp search-replace no-such-string other.example --dry-run --include-columns=option_value`
    Then STDOUT should be a table containing rows:
      | Table      | Column       | Replacements | Type |
      | wp_options | option_value | 0            | PHP  |

    When I run `wp search-replace match.example other.example`
    Then STDOUT should contain:
      """
      Success: Made 4 replacements.
      """

    When I run `wp option get sr_serialized_match --format=json`
    Then STDOUT should be:
      """
      {"url":"https:\/\/other.example\/x"}
      """

    When I run `wp option get sr_plain_match`
    Then STDOUT should be:
      """
      see https://other.example/y
      """

    When I run `wp post get {POST_ID} --field=post_content`
    Then STDOUT should be:
      """
      Plain other.example content
      """

  @require-mysql
  Scenario: Serialized array keys are left alone by default
    Given a WP install
    And a setup-recurse-keys.php file:
      """
      <?php
      update_option( 'recurse_keys_test', array( 'https://old.example.com/key' => 'https://old.example.com/value', 'nested' => array( 'https://old.example.com/inner' => 'plain' ) ) );
      """
    And a check-recurse-keys.php file:
      """
      <?php
      echo json_encode( get_option( 'recurse_keys_test' ), JSON_UNESCAPED_SLASHES );
      """
    And I run `wp eval-file setup-recurse-keys.php`

    When I run `wp search-replace 'https://old.example.com' 'https://new.example.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp eval-file check-recurse-keys.php`
    Then STDOUT should contain:
      """
      https://old.example.com/key
      """
    And STDOUT should contain:
      """
      https://new.example.com/value
      """
    And STDOUT should not contain:
      """
      https://new.example.com/key
      """

  @require-mysql
  Scenario: Search/replace serialized array keys with --recurse-keys
    Given a WP install
    And a setup-recurse-keys.php file:
      """
      <?php
      update_option( 'recurse_keys_test', array( 'https://old.example.com/key' => 'https://old.example.com/value', 'nested' => array( 'https://old.example.com/inner' => 'plain' ) ) );
      """
    And a check-recurse-keys.php file:
      """
      <?php
      echo json_encode( get_option( 'recurse_keys_test' ), JSON_UNESCAPED_SLASHES );
      """
    And I run `wp eval-file setup-recurse-keys.php`

    When I run `wp search-replace 'https://old.example.com' 'https://new.example.com' --recurse-keys`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp eval-file check-recurse-keys.php`
    Then STDOUT should contain:
      """
      https://new.example.com/key
      """
    And STDOUT should contain:
      """
      https://new.example.com/value
      """
    And STDOUT should contain:
      """
      https://new.example.com/inner
      """
    And STDOUT should not contain:
      """
      old.example.com
      """

  @require-mysql
  Scenario: Search/replace object property names with --recurse-keys
    Given a WP install
    And a setup-recurse-keys-object.php file:
      """
      <?php
      update_option( 'recurse_keys_object_test', (object) array( 'https://old.example.com/prop' => 'https://old.example.com/value' ) );
      """
    And a check-recurse-keys-object.php file:
      """
      <?php
      echo json_encode( get_option( 'recurse_keys_object_test' ), JSON_UNESCAPED_SLASHES );
      """
    And I run `wp eval-file setup-recurse-keys-object.php`

    When I run `wp search-replace 'https://old.example.com' 'https://new.example.com'`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp eval-file check-recurse-keys-object.php`
    Then STDOUT should contain:
      """
      https://old.example.com/prop
      """
    And STDOUT should contain:
      """
      https://new.example.com/value
      """

    When I run `wp eval-file setup-recurse-keys-object.php`
    And I run `wp search-replace 'https://old.example.com' 'https://new.example.com' --recurse-keys`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp eval-file check-recurse-keys-object.php`
    Then STDOUT should contain:
      """
      https://new.example.com/prop
      """
    And STDOUT should not contain:
      """
      old.example.com
      """

  @require-mysql
  Scenario: Refuse to rename colliding array keys with --recurse-keys
    Given a WP install
    And a setup-recurse-keys-collision.php file:
      """
      <?php
      update_option( 'recurse_keys_collision_test', array( 'https://old.example.com/key' => 'v1', 'https://new.example.com/key' => 'v2', 'other' => 'https://old.example.com/value' ), false );
      """
    And a check-recurse-keys-collision.php file:
      """
      <?php
      $value = get_option( 'recurse_keys_collision_test' );
      echo json_encode( $value, JSON_UNESCAPED_SLASHES );
      """
    And I run `wp eval-file setup-recurse-keys-collision.php`

    When I try `wp search-replace 'https://old.example.com' 'https://new.example.com' --recurse-keys`
    Then the return code should be 0
    And STDOUT should contain:
      """
      Success:
      """
    And STDERR should contain:
      """
      two keys would map onto the same key
      """

    When I run `wp eval-file check-recurse-keys-collision.php`
    Then STDOUT should contain:
      """
      "https://old.example.com/key":"v1"
      """
    And STDOUT should contain:
      """
      "https://new.example.com/key":"v2"
      """
    And STDOUT should contain:
      """
      "other":"https://new.example.com/value"
      """

  @require-mysql
  Scenario: Refuse to rename colliding object property names with --recurse-keys
    Given a WP install
    And a setup-recurse-keys-object-collision.php file:
      """
      <?php
      update_option( 'recurse_keys_object_collision_test', (object) array( 'https://old.example.com/prop' => 'v1', 'https://new.example.com/prop' => 'v2', 'other' => 'https://old.example.com/value' ), false );
      """
    And a check-recurse-keys-object-collision.php file:
      """
      <?php
      $value = get_option( 'recurse_keys_object_collision_test' );
      echo json_encode( $value, JSON_UNESCAPED_SLASHES );
      """
    And I run `wp eval-file setup-recurse-keys-object-collision.php`

    When I try `wp search-replace 'https://old.example.com' 'https://new.example.com' --recurse-keys`
    Then the return code should be 0
    And STDOUT should contain:
      """
      Success:
      """
    And STDERR should contain:
      """
      two property names would map onto the same name
      """

    When I run `wp eval-file check-recurse-keys-object-collision.php`
    Then STDOUT should contain:
      """
      "https://old.example.com/prop":"v1"
      """
    And STDOUT should contain:
      """
      "https://new.example.com/prop":"v2"
      """
    And STDOUT should contain:
      """
      "other":"https://new.example.com/value"
      """

  @require-mysql
  Scenario: Preserve shared references when renaming keys with --recurse-keys
    Given a WP install
    And a setup-recurse-keys-refs.php file:
      """
      <?php
      $shared = 'https://old.example.com/shared';
      update_option( 'recurse_keys_ref_test', array( 'https://old.example.com/a' => &$shared, 'b' => &$shared ), false );
      """
    And a check-recurse-keys-refs.php file:
      """
      <?php
      $raw = $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_ref_test'" );
      $value = get_option( 'recurse_keys_ref_test' );
      echo json_encode( $value, JSON_UNESCAPED_SLASHES ), "\n";
      echo false !== strpos( $raw, 'R:2;' ) ? 'HASREF' : 'NOREF';
      """
    And I run `wp eval-file setup-recurse-keys-refs.php`

    When I run `wp search-replace 'https://old.example.com' 'https://new.example.com' --recurse-keys`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp eval-file check-recurse-keys-refs.php`
    Then STDOUT should contain:
      """
      "https://new.example.com/a":"https://new.example.com/shared"
      """
    And STDOUT should contain:
      """
      HASREF
      """

  Scenario: Key collision detection with --recurse-keys compares keys as PHP stores them
    Given a WP install
    And a recurse-keys-storage-identity.php file:
      """
      <?php
      $replacer = new \WP_CLI\SearchReplacer( 'old', 'new', true, false, '', '/', false, -1, true );
      $data     = array(
          8     => 'v1',
          '08'  => 'v2',
          'old' => 'v3',
      );
      echo $replacer->run( serialize( $data ) ), "\n";
      echo $replacer->run( serialize( (object) $data ) ), "\n";
      """

    When I run `wp eval-file recurse-keys-storage-identity.php`
    Then STDERR should be empty
    And STDOUT should contain:
      """
      a:3:{i:8;s:2:"v1";s:2:"08";s:2:"v2";s:3:"new";s:2:"v3";}
      """
    And STDOUT should contain:
      """
      s:3:"new";s:2:"v3";}
      """
    And STDOUT should not contain:
      """
      "old"
      """

  Scenario: Overlapping property names are renamed without losing values with --recurse-keys
    Given a WP install
    And a recurse-keys-overlap.php file:
      """
      <?php
      $replacer = new \WP_CLI\SearchReplacer( 'old', 'newold', true, false, '', '/', false, -1, true );
      $data     = array(
          'old'    => 'v1',
          'newold' => 'v2',
      );
      $result   = unserialize( $replacer->run( serialize( (object) $data ) ) );
      echo json_encode( $result );
      """

    When I run `wp eval-file recurse-keys-overlap.php`
    Then STDERR should be empty
    And STDOUT should contain:
      """
      "newold":"v1"
      """
    And STDOUT should contain:
      """
      "newnewold":"v2"
      """

  # `CaseInsensitiveDictionary` is from Requests 2.0, which was added in 6.2.
  @require-wp-6.2
  Scenario: Case-insensitive dictionary offsets are not renamed onto an existing offset with --recurse-keys
    Given a WP install
    And a recurse-keys-case-insensitive.php file:
      """
      <?php
      WP_CLI::add_hook(
          'search_replace_unserialize_options',
          function () {
              return [ 'allowed_classes' => [ 'WpOrg\Requests\Utility\CaseInsensitiveDictionary' ] ];
          }
      );
      $replacer = new \WP_CLI\SearchReplacer( 'old', 'NEW', true, false, '', '/', false, -1, true );
      $result   = unserialize(
          $replacer->run(
              serialize(
                  new \WpOrg\Requests\Utility\CaseInsensitiveDictionary(
                      [
                          'old' => 'v1',
                          'new' => 'v2',
                      ]
                  )
              )
          ),
          [ 'allowed_classes' => [ 'WpOrg\Requests\Utility\CaseInsensitiveDictionary' ] ]
      );
      echo json_encode( $result->getAll() );
      """

    When I try `wp eval-file recurse-keys-case-insensitive.php`
    Then STDERR should contain:
      """
      two property names would map onto the same name
      """
    And STDOUT should contain:
      """
      "old":"v1"
      """
    And STDOUT should contain:
      """
      "new":"v2"
      """

  @require-mysql
  Scenario: Keep the original key when a regex replacement fails with --recurse-keys
    Given a WP install
    And a setup-recurse-keys-pcre.php file:
      """
      <?php
      update_option( 'recurse_keys_pcre', array( 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!' => 'keep!' ) );
      """
    And a check-recurse-keys-pcre.php file:
      """
      <?php
      echo json_encode( get_option( 'recurse_keys_pcre' ) );
      """
    And I run `wp eval-file setup-recurse-keys-pcre.php`

    When I try `wp search-replace '^(a+\s?)+$' 'x' wp_options --include-columns=option_value --regex --recurse-keys`
    Then STDERR should contain:
      """
      The provided regular expression threw a PCRE error
      """

    When I run `wp eval-file check-recurse-keys-pcre.php`
    Then STDOUT should be:
      """
      {"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!":"keep!"}
      """

  @require-mysql
  Scenario: Do not log rejected key renames with --recurse-keys --log
    Given a WP install
    And a setup-recurse-keys-log.php file:
      """
      <?php
      update_option( 'recurse_keys_log_test', array( 'oldtok/key' => 'v1', 'newtok/key' => 'v2', 'other' => 'oldtok/value' ), false );
      """
    And I run `wp eval-file setup-recurse-keys-log.php`

    When I try `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys --log`
    Then STDERR should contain:
      """
      two keys would map onto the same key
      """
    And STDOUT should contain:
      """
      < oldtok/value
      """
    And STDOUT should contain:
      """
      > newtok/value
      """
    And STDOUT should not contain:
      """
      oldtok/key
      """

  @require-mysql @require-php-8.1
  Scenario: Keep readonly property names and all values when renaming property names with --recurse-keys
    Given a WP install
    And a wp-content/mu-plugins/recurse-keys-readonly.php file:
      """
      <?php
      #[AllowDynamicProperties]
      class Recurse_Keys_Readonly_Test {
          public $oldtok_mutable;
          public readonly string $oldtok_ro;
          public function __construct( $mutable, $ro ) {
              $this->oldtok_mutable = $mutable;
              $this->oldtok_ro      = $ro;
          }
      }
      if ( class_exists( 'WP_CLI' ) ) {
          WP_CLI::add_hook(
              'search_replace_unserialize_options',
              function () {
                  return [ 'allowed_classes' => [ 'stdClass', 'Recurse_Keys_Readonly_Test' ] ];
              }
          );
      }
      """
    And a setup-recurse-keys-readonly.php file:
      """
      <?php
      update_option( 'recurse_keys_readonly_test', array( 'item' => new Recurse_Keys_Readonly_Test( 'keep-mutable', 'keep-ro' ) ), false );
      """
    And a check-recurse-keys-readonly.php file:
      """
      <?php
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_readonly_test'" );
      """
    And I run `wp eval-file setup-recurse-keys-readonly.php`

    When I try `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys`
    Then the return code should be 0

    When I run `wp eval-file check-recurse-keys-readonly.php`
    Then STDOUT should contain:
      """
      s:9:"oldtok_ro";s:7:"keep-ro";
      """
    And STDOUT should contain:
      """
      s:14:"newtok_mutable";s:12:"keep-mutable";
      """
    And STDOUT should not contain:
      """
      "oldtok_mutable"
      """

  @require-mysql
  Scenario: Preserve shared object property references when renaming property names with --recurse-keys
    Given a WP install
    And a setup-recurse-keys-object-refs.php file:
      """
      <?php
      $object               = new stdClass();
      $object->{'oldtok/a'} = 'shared';
      $object->b            = &$object->{'oldtok/a'};
      update_option( 'recurse_keys_object_ref_test', array( 'item' => $object ), false );
      """
    And a check-recurse-keys-object-refs.php file:
      """
      <?php
      $raw = $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_object_ref_test'" );
      echo $raw, "\n";
      echo preg_match( '/[Rr]:\d+;/', $raw ) ? 'HASREF' : 'NOREF', "\n";
      $value            = get_option( 'recurse_keys_object_ref_test' );
      $value['item']->b = 'changed';
      echo $value['item']->{'newtok/a'};
      """
    And I run `wp eval-file setup-recurse-keys-object-refs.php`

    When I run `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp eval-file check-recurse-keys-object-refs.php`
    Then STDOUT should contain:
      """
      s:8:"newtok/a";
      """
    And STDOUT should contain:
      """
      "shared"
      """
    And STDOUT should contain:
      """
      HASREF
      """
    And STDOUT should contain:
      """
      changed
      """

  @require-mysql
  Scenario: Keep the order of numeric object property names that are not renamed with --recurse-keys
    Given a WP install
    And a setup-recurse-keys-numeric-property.php file:
      """
      <?php
      $object        = new stdClass();
      $object->{'8'} = 'top';
      $object->label = 'keep';
      update_option( 'recurse_keys_numeric_property_test', array( 'item' => $object, 'other' => 'oldtok' ), false );
      """
    And a check-recurse-keys-numeric-property.php file:
      """
      <?php
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_numeric_property_test'" );
      """
    And I run `wp eval-file setup-recurse-keys-numeric-property.php`

    When I run `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys`
    Then STDOUT should contain:
      """
      Success:
      """

    When I run `wp eval-file check-recurse-keys-numeric-property.php`
    Then STDOUT should be:
      """
      a:2:{s:4:"item";O:8:"stdClass":2:{s:1:"8";s:3:"top";s:5:"label";s:4:"keep";}s:5:"other";s:6:"newtok";}
      """

    When I run `wp search-replace 'stdClass' 'otherClass' wp_options --include-columns=option_value --recurse-keys --dry-run --report-changed-only`
    Then STDOUT should not contain:
      """
      wp_options
      """

  @require-mysql
  Scenario: Leave the stored value unchanged when removing a property throws an exception with --recurse-keys
    Given a WP install
    And a wp-content/mu-plugins/recurse-keys-throwing-unset.php file:
      """
      <?php
      class Recurse_Keys_Throwing_Unset_Test extends ArrayObject {
          public static $unset_calls = 0;
          #[ReturnTypeWillChange]
          public function offsetUnset( $key ) {
              if ( 2 === ++self::$unset_calls ) {
                  throw new Exception( 'second removal failed' );
              }
              parent::offsetUnset( $key );
          }
      }
      if ( class_exists( 'WP_CLI' ) ) {
          WP_CLI::add_hook(
              'search_replace_unserialize_options',
              function () {
                  return [ 'allowed_classes' => [ 'stdClass', 'Recurse_Keys_Throwing_Unset_Test' ] ];
              }
          );
      }
      """
    And a setup-recurse-keys-throwing-unset.php file:
      """
      <?php
      $object = new Recurse_Keys_Throwing_Unset_Test( array( 'oldtok_a' => 'value-a', 'keep' => 'value-keep', 'oldtok_b' => 'value-b' ) );
      update_option( 'recurse_keys_throwing_unset_test', array( 'item' => $object ), false );
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_throwing_unset_test'" );
      """
    And a check-recurse-keys-throwing-unset.php file:
      """
      <?php
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_throwing_unset_test'" );
      """
    And I run `wp eval-file setup-recurse-keys-throwing-unset.php`
    And save STDOUT as {ORIGINAL}

    When I try `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys`
    Then the return code should be 0

    When I run `wp eval-file check-recurse-keys-throwing-unset.php`
    Then STDOUT should be:
      """
      {ORIGINAL}
      """
    And STDOUT should contain:
      """
      s:8:"oldtok_a";s:7:"value-a";s:4:"keep";s:10:"value-keep";s:8:"oldtok_b";s:7:"value-b";
      """

  @require-mysql
  Scenario: Leave the stored value unchanged when an immutable offset sits between renamed offsets with --recurse-keys
    Given a WP install
    And a wp-content/mu-plugins/recurse-keys-immutable-offset.php file:
      """
      <?php
      class Recurse_Keys_Immutable_Offset_Test extends ArrayObject {
          #[ReturnTypeWillChange]
          public function offsetSet( $key, $value ) {
              if ( 'keep' === $key ) {
                  throw new Exception( 'keep is immutable' );
              }
              parent::offsetSet( $key, $value );
          }
          #[ReturnTypeWillChange]
          public function offsetUnset( $key ) {
              if ( 'keep' === $key ) {
                  throw new Exception( 'keep is immutable' );
              }
              parent::offsetUnset( $key );
          }
      }
      if ( class_exists( 'WP_CLI' ) ) {
          WP_CLI::add_hook(
              'search_replace_unserialize_options',
              function () {
                  return [ 'allowed_classes' => [ 'stdClass', 'Recurse_Keys_Immutable_Offset_Test' ] ];
              }
          );
      }
      """
    And a setup-recurse-keys-immutable-offset.php file:
      """
      <?php
      $object = new Recurse_Keys_Immutable_Offset_Test( array( 'oldtok_a' => 'value-a', 'keep' => 'value-keep', 'oldtok_b' => 'value-b' ) );
      update_option( 'recurse_keys_immutable_offset_test', array( 'item' => $object, 'other' => 'oldtok-other' ), false );
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_immutable_offset_test'" );
      """
    And a check-recurse-keys-immutable-offset.php file:
      """
      <?php
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_immutable_offset_test'" );
      """
    And I run `wp eval-file setup-recurse-keys-immutable-offset.php`
    And save STDOUT as {ORIGINAL}

    When I try `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys`
    Then the return code should be 0
    And STDERR should contain:
      """
      the whole value was left unchanged
      """

    When I run `wp eval-file check-recurse-keys-immutable-offset.php`
    Then STDOUT should be:
      """
      {ORIGINAL}
      """
    And STDOUT should contain:
      """
      s:8:"oldtok_b";s:7:"value-b";
      """

  @require-mysql
  Scenario: Leave the stored value unchanged when removing an offset throws after removing it with --recurse-keys
    Given a WP install
    And a wp-content/mu-plugins/recurse-keys-unset-then-throw.php file:
      """
      <?php
      class Recurse_Keys_Unset_Then_Throw_Test extends ArrayObject {
          #[ReturnTypeWillChange]
          public function offsetUnset( $key ) {
              parent::offsetUnset( $key );
              if ( 'oldtok_b' === $key ) {
                  throw new Exception( 'removed oldtok_b, then failed' );
              }
          }
      }
      if ( class_exists( 'WP_CLI' ) ) {
          WP_CLI::add_hook(
              'search_replace_unserialize_options',
              function () {
                  return [ 'allowed_classes' => [ 'stdClass', 'Recurse_Keys_Unset_Then_Throw_Test' ] ];
              }
          );
      }
      """
    And a setup-recurse-keys-unset-then-throw.php file:
      """
      <?php
      $object = new Recurse_Keys_Unset_Then_Throw_Test( array( 'oldtok_a' => 'value-a', 'keep' => 'value-keep', 'oldtok_b' => 'value-b' ) );
      update_option( 'recurse_keys_unset_then_throw_test', array( 'item' => $object, 'other' => 'oldtok-other' ), false );
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_unset_then_throw_test'" );
      """
    And a check-recurse-keys-unset-then-throw.php file:
      """
      <?php
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_unset_then_throw_test'" );
      """
    And I run `wp eval-file setup-recurse-keys-unset-then-throw.php`
    And save STDOUT as {ORIGINAL}

    When I try `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys`
    Then the return code should be 0
    And STDERR should contain:
      """
      the whole value was left unchanged
      """

    When I run `wp eval-file check-recurse-keys-unset-then-throw.php`
    Then STDOUT should be:
      """
      {ORIGINAL}
      """
    And STDOUT should contain:
      """
      s:8:"oldtok_b";s:7:"value-b";
      """

  @require-mysql @require-php-8.1
  Scenario: Leave nested objects unchanged when a readonly property of their parent cannot be updated with --recurse-keys
    Given a WP install
    And a wp-content/mu-plugins/recurse-keys-readonly-parent.php file:
      """
      <?php
      class Recurse_Keys_Readonly_Parent_Test {
          public readonly string $label;
          public $child;
          public function __construct( $label, $child ) {
              $this->label = $label;
              $this->child = $child;
          }
      }
      if ( class_exists( 'WP_CLI' ) ) {
          WP_CLI::add_hook(
              'search_replace_unserialize_options',
              function () {
                  return [ 'allowed_classes' => [ 'stdClass', 'Recurse_Keys_Readonly_Parent_Test' ] ];
              }
          );
      }
      """
    And a setup-recurse-keys-readonly-parent.php file:
      """
      <?php
      $child               = new stdClass();
      $child->oldtok_child = 'value-child';
      update_option( 'recurse_keys_readonly_parent_test', array( 'item' => new Recurse_Keys_Readonly_Parent_Test( 'oldtok-label', $child ) ), false );
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_readonly_parent_test'" );
      """
    And a check-recurse-keys-readonly-parent.php file:
      """
      <?php
      echo $GLOBALS['wpdb']->get_var( "SELECT option_value FROM {$GLOBALS['wpdb']->options} WHERE option_name = 'recurse_keys_readonly_parent_test'" );
      """
    And I run `wp eval-file setup-recurse-keys-readonly-parent.php`
    And save STDOUT as {ORIGINAL}

    When I try `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys`
    Then the return code should be 0
    And STDERR should contain:
      """
      Cannot modify readonly property
      """

    When I run `wp eval-file check-recurse-keys-readonly-parent.php`
    Then STDOUT should be:
      """
      {ORIGINAL}
      """
    And STDOUT should contain:
      """
      s:12:"oldtok_child";s:11:"value-child";
      """

  @require-mysql
  Scenario: Do not log a value that is left unchanged after a failed key replacement with --recurse-keys --log
    Given a WP install
    And a wp-content/mu-plugins/recurse-keys-failing-log.php file:
      """
      <?php
      class Recurse_Keys_Failing_Log_Test extends ArrayObject {
          #[ReturnTypeWillChange]
          public function offsetUnset( $key ) {
              throw new Exception( 'removal failed' );
          }
      }
      if ( class_exists( 'WP_CLI' ) ) {
          WP_CLI::add_hook(
              'search_replace_unserialize_options',
              function () {
                  return [ 'allowed_classes' => [ 'stdClass', 'Recurse_Keys_Failing_Log_Test' ] ];
              }
          );
      }
      """
    And a setup-recurse-keys-failing-log.php file:
      """
      <?php
      $object = new Recurse_Keys_Failing_Log_Test( array( 'oldtok_a' => 'oldtok-discarded-value' ) );
      update_option( 'recurse_keys_failing_log_a', array( 'item' => $object, 'other' => 'oldtok-discarded-sibling' ), false );
      update_option( 'recurse_keys_failing_log_b', array( 'other' => 'oldtok/next-row' ), false );
      """
    And I run `wp eval-file setup-recurse-keys-failing-log.php`

    When I try `wp search-replace 'oldtok' 'newtok' wp_options --include-columns=option_value --recurse-keys --log`
    Then the return code should be 0
    And STDOUT should contain:
      """
      < oldtok/next-row
      """
    And STDOUT should not contain:
      """
      oldtok-discarded
      """
    And STDOUT should contain:
      """
      Success: Made 1 replacement.
      """
