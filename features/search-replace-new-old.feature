Feature: Do a search/replace with --new and --old arguments

  Scenario: Basic search/replace
    Given a WP install

    When I run `wp post create --post_title=bar --post_content='This is a text with --dash' --porcelain`
    Then save STDOUT as {POST_ID}

    When I run `wp search-replace --old=bar --new=burrito wp_post\?`
    And STDOUT should be a table containing rows:
      | Table         | Column      | Replacements | Type |
      | wp_posts      | post_title  | 1            | SQL  |

    When I run `wp post get {POST_ID} --field=title`
    Then STDOUT should be:
      """
      burrito
      """

    When I run `wp search-replace --old='--dash' --new='no dash' wp_posts`
    And STDOUT should be a table containing rows:
      | Table         | Column        | Replacements | Type |
      | wp_posts      | post_content  | 1            | SQL  |
    
    When I try `wp search-replace --old=foo bar`
    And STDERR should be:
      """
      Error: Argument --new needs to be provided.
      """
