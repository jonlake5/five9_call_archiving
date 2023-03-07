import urllib.parse

bucket_name = 'jlake-bot3'
region = 'us-west-2'
key = 'Boys Kayaking 2.jpg'
url = "https://%s.s3.%s.amazonaws.com/%s" % (
    bucket_name,
    region,
    urllib.parse.quote(key, safe="~()*!.'"),
)
print(url)

