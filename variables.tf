locals {
  domain_name = "domain.com" 
  region = "us-east-1"
  env_class = "production"
  
  # the below properties are for auth0
  # they only need to be set if support_auth0 = 1
  support_auth0 = 1 # 0 = do not setup auth0 DNS entries, 1 = setup auth0 DNS entries
  auth0_domain = "domain.auth0.com" # your auth0 subdomain
  auth0_alias = "auth" # the CNAME that will serve auth0 from your domain
}