require 'sinatra'
require 'redis'
require 'json'

configure do
  #uri = URI.parse(ENV["RTOGO_URL"])
  # should use heroku config:add instead
  uri = URI.parse('redis://redistogo:3070c66f8128f4eefbc06a484aac8bca@barb.redistogo.com:9048/')

  R = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

##########
# routers
##########

# index page with a search form
get '/' do

	@category_names = R.smembers "category_names"

	erb :index
end

# index page with a search form and results
post '/search' do
	open 		= params[:open] # true or false
	sort 		= params[:sort] # asc or desc
	order 		= params[:order] # alpha or end_date or relevance
	keywords 	= params[:keywords] || "" # as a string
	categories 	= params[:categories] || nil # from checkboxes

	# process keywords string into a list of keywords
	keywords = keywords.downcase.split.uniq
	keywords = keywords.length > 0 ? keywords : nil

	# do search
	ids = search(open, sort, order, keywords, categories)

	# build up results
	results = []

	# maybe more efficient way than this
	ids.each do |id|
		result = {}
		result["id"] = id
		result["title"] = R.get "title:"+ id
		result["open"] = R.get "open:"+ id
		result["end_date"] = R.get "end_date:"+ id
		result["categories"] = R.smembers "categories:"+ id

		results.push(result)
	end
	
	# output results as json
	content_type :json
	results.to_json 
end

# post page to post challenges.json
# maybe we could simply password protect this page
get '/post' do
	erb :post
end

# maybe we could simply password protect this page
post '/post' do

	_json = params[:json]

	challenges = JSON.parse(_json)

	challenges.each do |c|
		# important attributes of a challenge
		# c['Id'], c['Name'], c['End_Date__c'], c['Challenge_Categories__r']['records']['Id'], 
		# c['Top_Prize_c'], c['Is_Open__c'], c['Registered_Members_c']
		
		# check if the challenge is existent
		if R.get "title:"+ c['Id']
			update_challenge(c)
		else
			create_challenge(c)
		end
	end

	"posted"
end

##########
# functions
##########

# create challenge
def create_challenge(c)

	challenge_id = c["ID__c"] || c["Challenge_Id__c"]

	# add title
	R.set "title:"+ challenge_id, c["Name"]

	# add title keywords - for keyword search
	create_keyword_index(challenge_id, c["Name"])

	# add categories
	categories = c['Challenge_Categories__r']['records']
	categories.each do |category|
		# add the id to the set to category:category_name
		R.sadd "category:"+ category["Display_Name__c"], challenge_id

		# just to keep track of available categories
		R.sadd "category_names", category["Display_Name__c"]
		R.sadd "categories:"+ challenge_id, category["Display_Name__c"]
	end

	# open/closed challenge
	if c["Is_Open__c"] == "true"
		R.sadd "open_challenges", challenge_id
	else
		R.sadd "closed_challenges", challenge_id
	end

	# add open
	R.set "open:"+ challenge_id, c["Is_Open__c"]

	# add end_date
	R.set "end_date:"+ challenge_id, c["End_Date__c"]

end

# delete challenge
def delete_challenge(c)

	challenge_id = c["ID__c"] || c["Challenge_Id__c"]

	# delete title
	R.del "title:"+ challenge_id

	# delete title keywords - for keyword search
	delete_keyword_index(challenge_id)

	# delete categories
	categories = c['Challenge_Categories__r']['records']
	categories.each do |category|
		# remove the id from the set of category:category_name
		R.srem "category:"+ category["Display_Name__c"], challenge_id

		if R.smembers "category:", category["Display_Name__c"] == []
			R.srem "category_names", category["Display_Name__c"]
		end
		R.srem "categories:"+ challenge_id, category["Display_Name__c"]
	end

	# open/closed challenge
	R.srem "open_challenges", challenge_id
	R.srem "closed_challenges", challenge_id

	# delete open
	R.del "open:"+ challenge_id

	# delete end_date
	R.del "end_date:"+ challenge_id

end

# update challenge
def update_challenge(c)

	# delete it cleanly
	delete_challenge(c)

	# then create it
	create_challenge(c)

end

def create_keyword_index(id, text)

	# just some overused words
	ignore_these = ["the", "a", "an", "is", "are", "on", "at", "then", "for", "from", "at", "this", "that", "more"]

	keywords = text.downcase.split.uniq - ignore_these

	keywords.each do |keyword|
		metaphones = metaphones_for_keyword(keyword)

		metaphones.each do |kw|
			# add id to keyword:keyword set
			R.sadd "keyword:"+ kw, id

			# add keyword to keywords:id set
			R.sadd "keywords:"+ id, kw
		end

	end
end

def delete_keyword_index(id)

	# get keywords for this challenge
	keywords = R.smembers "keywords:"+ id
	
	# loop through each of them
	keywords.each do |keyword|
		# remove id from keyword:keyword set
		R.srem "keyword:"+ keyword, id

		# remove keyword from keywords:id set
		R.srem "keywords:"+ id, keyword
	end
end

# do search
def search(open = "true", by = "title", order= "asc", keywords = nil, categories = nil, inclusive = true)
	_by = {"title" => "title:*", "end_date" => "end_date:*"}

	order += " ALPHA"
	
	if keywords or categories
		# advanced search

		# set sort to "relevance"
		# sort = "relevance"

		keywords_ids = keywords ? search_by_keyword(keywords, inclusive) : []
		categories_ids = categories ? search_by_category(categories, inclusive) : []

		if keywords and categories
			ids = keywords_ids & categories_ids
		else
			ids = keywords_ids + categories_ids
		end

		# sort by relevance - arrange by frequency of ids
		ids = ids.group_by{|i| i}.sort_by{ |k,v| -v.length }.map{|k,v| k}

		# only list open/closed challenges
		_challenges = open == "true" ? "open_challenges" : "closed_challenges"
		_challenges_ids = R.smembers _challenges

		ids = ids & _challenges_ids # intersection of these two arrays of ids

		# sort by relvance or other things
		if by == "relevance"
			return ids
		else
			uuid = Time.new.to_i + rand(999999) # just for temp purpose, to create a list in redis
			uuid = uuid.to_s()

			# create a temp list in redis for sorting
			ids.each do |id|
				R.lpush "search:"+ uuid, id
			end

			return R.sort "search:"+ uuid, :by => _by[by], :order => order.upcase
		end
	else
		# basic search

		# only list open/closed challenges
		_challenges = open == "true" ? "open_challenges" : "closed_challenges"

		return R.sort _challenges, :by => _by[by], :order => order.upcase
	end
end

# search by keyword(s)
def search_by_keyword(keywords, inclusive)
	# get metaphones for each keyword
	metaphones = keywords.map {|keyword| metaphones_for_keyword(keyword)}.compact.flatten

	# get redis keys for all the metaphone
	redis_keys = metaphones.map {|metaphone| "keyword:"+ metaphone}.compact

	# get the union of the set, then we get ids
	if inclusive
		ids = R.sunion(redis_keys)
	else
		ids = R.sinter(redis_keys) # exclusive - intersect
	end

	return ids
end

# search by category(s)
def search_by_category(categories, inclusive)
	# get redis keys for all the categories
	redis_keys = categories.map {|category| "category:"+ category}.compact

	# get the union of the set, then we get ids
	if inclusive
		ids = R.sunion(redis_keys) # inclusive - union
	else
		ids = R.sinter(redis_keys) # exclusive - intersect
	end

	return ids
end

# metaphones/typos for the word
# modified from - http://text.rubyforge.org/svn/lib/text/metaphone.rb
def metaphones_for_keyword(keyword, buggy = true)

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