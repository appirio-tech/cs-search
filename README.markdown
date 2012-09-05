# demo 

http://cs-search.herokuapp.com/

# source

https://bitbucket.org/soe/cs-search/get/master.zip

# overview

- built on Sinatra, deployed on Heroku with RedisToGo
- http://cs-search.herokuapp.com/post to post challenges JSON
- search support keyword index with metaphones/typos/mis-spellings

# endpoints

- '/' - main page with search form
- '/search' - accepts post request, return json of challenges
- '/post' - an easy form to upload challenges.json

# structure

- web.rb ... main file with controllers/routers, and functions
- views/ ... erb views

# redis structure

Keyword based search index
> (Sets) keyword:<keyword>, (Sets) keyword:<id>

To store minimal required data for each challenge
> (Keys) title:<id>, (Keys) end_date:<id>, (Keys) open:<id>, (Sets) categories:<id>, (Sets) category:<category_name>

To keep track of open and closed challenges
> (Sets) open_challenges, (Sets) closed_challenges

To keep track of categories
> (Sets) category_names

# deployment

1. clone this git repository
> git clone https://bitbucket.org/soe/cs-search.git
2. then create a heroku project
> heroku create <project name>
3. then push to heroku
> git push heroku master
4. then update ENV["RTOGO_URL"]

# functions

Following functions worth special mention...
For all functions,please refer to inline comments...

search(open = true, sort = "alpha", order= "asc", keywords = nil, categories = nil, inclusive = true)
> do various searches with sorting

metaphones_for_keyword(keyword, buggy = true)
> generate list of metaphones: typos, mis-spellings

# screencast

https://vimeo.com/45731039