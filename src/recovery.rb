# TODO allow recovery of unposted events

require 'rack'
require './src/functions'

# @precondition -> variables do not exist in header
# @param text -> text to be parsed
# @return -> undefined (not important)
# @postcondition -> session variables are set
def parse_sections(text)
  sections = {}

  # parse the full post into individual sections
  text.scan(
    %r{\[\]\(/# MC // (.*)\)\n((?:.*\n)*?)(?=\[\]\(/# MC //.*\))}
  ).each do |name, content|
    # don't combine this and setting session variables, as events need parsing
    sections[name.downcase.to_sym] = content.strip
  end

  # parse the events section (if it exists)
  if sections.key?(:events) && sections[:events].length > 49
    events = []
    # [49..-1] strips header
    sections[:events][49..-1].scan(/\| (.*) \| (.*) \|/) do |time, message|
      events.push [true, time, message]
    end
  end
  sections[:events] = events

  # set session variables with parsed values
  sections.each do |key, value|
    session[key] = value
  end

  sections
end

# @precondition -> variables exist in header
# @param text -> the full text to be parsed, including unimportant sections
# @return -> [{variables}, initial text with variables stripped]
# @postcondition -> session variables are set
def parse_vars(text)
  # isolate the variables string
  vars, sections = text.split('[](/# MC // END VARS)', 2)

  # parse the variables & set in session variables
  vars.scan(%r{\[\]\(\/# MC // let (.*) = (.*)\)}) do |name, value|
    session[name.downcase.to_sym] = value == 'null' ? nil : value
  end

  sections.strip
end

# @param url -> valid URL to reddit post
# @return -> boolean if recovery succeeded
# @postcondition -> session variables are set if recovery succeeded
def recover_post(url)
  id = %r{(?:www).reddit.com/r/(?:.*?)/comments/([0-9a-z]{6})}.match(url)
  post = (request.env['redd.session'].from_ids ["t3_#{id[1]}"].to_ary)[0]

  # require self post
  return false unless post.is_self

  # require OP to be current user
  return false unless request.env['redd.session'].me.name != post.author

  # set everything into session variables
  parse_sections parse_vars post.selftext
  session[:post] = post.id

  true
end
