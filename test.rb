require 'sinatra'
require 'redis'
require 'json'

configure do
  require 'redis'
  #uri = URI.parse(ENV["RTOGO_URL"])
  uri = URI.parse('redis://redistogo:3070c66f8128f4eefbc06a484aac8bca@barb.redistogo.com:9048/')
  R = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end


# metaphones/typos for the word
# modified from - http://text.rubyforge.org/svn/lib/text/metaphone.rb
def metaphone_for_keyword(keyword, buggy = true)

	_standard = [ 
      # Regexp, replacement
      [ /([bcdfhjklmnpqrstvwxyz])\1+/, '\1' ],  # Remove doubled consonants except g. # [PHP] remove c from regexp.
      [ /^ae/,            'E' ],
      [ /^[gkp]n/,        'N' ],
      [ /^wr/,            'R' ],
      [ /^x/,             'S' ],
      [ /^wh/,            'W' ],
      [ /mb$/,            'M' ],  # [PHP] remove $ from regexp.
      [ /(?!^)sch/,      'SK' ],
      [ /th/,             '0' ],
      [ /t?ch|sh/,        'X' ],
      [ /c(?=ia)/,        'X' ],
      [ /[st](?=i[ao])/,  'X' ],
      [ /s?c(?=[iey])/,   'S' ],
      [ /[cq]/,           'K' ],
      [ /dg(?=[iey])/,    'J' ],
      [ /d/,              'T' ],
      [ /g(?=h[^aeiou])/, ''  ],
      [ /gn(ed)?/,        'N' ],
      [ /([^g]|^)g(?=[iey])/, '\1J' ],
      [ /g+/,             'K' ],
      [ /ph/,             'F' ],
      [ /([aeiou])h(?=\b|[^aeiou])/, '\1' ],
      [ /[wy](?![aeiou])/, '' ],
      [ /z/,              'S' ],
      [ /v/,              'F' ],
      [ /(?!^)[aeiou]+/,  ''  ],
    ]
  
    # The rules for the 'buggy' alternate implementation used by PHP etc.
    _buggy = _standard.dup
    _buggy[0] = [ /([bdfhjklmnpqrstvwxyz])\1+/, '\1' ]
    _buggy[6] = [ /mb/, 'M' ]

	# Normalise case and remove non-ASCII
	s = keyword.downcase.gsub(/[^a-z]/, '')
	# Apply the Metaphone rules
	rules = buggy ? _buggy : _standard

	metaphones = []

	rules.each do |rule|
		_s = s.gsub(rule[0], rule[1])
		if _s != s
			metaphones.push(_s)
		end
	end

	metaphones = rules.map {|rule| s.gsub(rule[0], rule[1])}.compact

	metaphones.delete(s)
	metaphones.push(s)

	return metaphones
end