# Setup infrastructure using Terraform to serve a SPA from Cloudfront

Follow along to use Terraform to create a content delivery network (CDN) using [AWS's Cloudfront](https://aws.amazon.com/cloudfront/).

## Why AWS and Terraform?

* Provision infrastructure in AWS due to economies of scale.
* Manage infrastructure as code (IaC) for consistency and supportability.
* Use Terraform for IaC because it has great documentation and is flexible.

My estimated monthly cost is $0.57, and [will easily stay in the free tier for the first year](https://aws.amazon.com/cloudfront/pricing/?nc=sn&loc=3). Note: this could go up in the future, as I layer on addtional services.

## Tutorial

### Limitations

If you decide to use this and are not in North America, you'll have to make a couple small changes to accomodate your region. Refer to `price_class` and `restrictions` in [main.tf](./main.tf) and update accordingly.

### Getting Started

Clone or fork and clone this repo.

### Signup for AWS & Create a user for IaC

1. [Sign up for AWS](https://portal.aws.amazon.com/billing/signup#/start)
   1. Do NOT use keys associated with the Root User for IaC.
   2. Create a user and group for IaC in the next step.
2. Create a user and group
   1. [Create a new group](https://console.aws.amazon.com/iam/home#/groups)
      1. Name it `IaC`, or whatever you like
      2. Go to the `Permissions` tab, click `Attach Policy` and attach  `AdministratorAccess`
   2. [Create a new user](https://console.aws.amazon.com/iam/home#/users)
      1. Set `User name` to `TerraformCLI` or whatever you like
      2. Be sure to select the `Programmatic Access` checkbox to create related keys
      3. Save the `access key` and `secret access key` in a safe place, back them up accordingly
   3. [Additional reading](https://docs.aws.amazon.com/IAM/latest/UserGuide/getting-started_create-admin-group.html#getting-started_create-admin-group-console)
3. [Consider blocking public access for all S3 buckets.](https://s3.console.aws.amazon.com/s3/settings)

### A domain

You must have a domain to administer, including the ability to set its related name servers.

I happened to use a domain from GoDaddy, but, you can purchase one using AWS too.

### Install software

You don't have to use `arkade`, but, [it makes life easier, especially if you work with Kubernetes](https://github.com/alexellis/arkade).

```bash
# Get arkade
# Note: you can also run without `sudo` and move the binary yourself
curl -sLS https://dl.get-arkade.dev | sudo sh
arkade --help
ark --help  # a handy alias
```

```bash
# Get terraform using arkade
ark get terraform
sudo mv $HOME/.arkade/bin/terraform /usr/local/bin/
```

```bash
# Get the aws cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
echo $'\naws' >> .gitignore
rm awscliv2.zip
aws --version
```

### Set environment variables used by AWS and Terraform CLIs

These values are the ones you would have saved when creating the IaC user.

```bash
# Setup AWS to use the keys from your IaC account
export AWS_ACCESS_KEY_ID=$MY_AWS_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$MY_AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$MY_AWS_REGION
```

### Setup an AWS S3 bucket to persist Terraform State

Creating an S3 bucket to persist Terraform state is **optional**. You can use the [local backend, which I did at first, or another backend](https://www.terraform.io/docs/language/settings/backends/index.html).

```bash
# Name the S3 bucket 
TF_STATE_BUCKET_NAME="s3-my-cool-state-bucket-name"
```

Let's create the bucket using the AWS CLI. [For reference, here is the AWS CLI S3 API](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3api/index.html#cli-aws-s3api).

```bash
# Make sure the AWS ENV variables are already set

# Create a bucket
aws s3api create-bucket --bucket $TF_STATE_BUCKET_NAME \
--acl private --region $AWS_DEFAULT_REGION \
--object-lock-enabled-for-bucket

# Update to add versioning
aws s3api put-bucket-versioning --bucket $TF_STATE_BUCKET_NAME \
--versioning-configuration Status=Enabled

# Update to add encryption
aws s3api put-bucket-encryption --bucket $TF_STATE_BUCKET_NAME \
--server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
```

### Configure Terraform

At this point, we just have to set a few more things.

Set [variables in `variables.tf`](./variables.tf):

1. Change values as needed (generally just your purchased `domain`, and desired AWS `region`)
2. If you use `auth0`, consider setting `support_auth0` to `1`.
   1. This creates a CNAME entry for a related auth0 custom domain (requires additional setup in `auth0`)

Set [properties in `backend.tf` for your desired Terraform backend](./backend.tf):

1. Change values as needed. If using `S3` as the backend, generally just `bucket`, and `region`

### Use Terraform

Initialize Terraform, which'll create some files, load remote state (if any), and download modules needed to provision your infrastructure.

```bash
# initialize terraform, make sure your AWS ENV variables are set in this context
cd to/this/folder
terraform init # this can even copy local state to a remote backend like S3!
```

#### Plan infrastructure changes

Run `terraform plan`.

This will ask Terraform to create and output a report of what it would do (create/update/delete), if it were deploying changes (the next step).

#### Create or update infrastructure

Run `terraform apply`, and enter `yes` if the plan looks okay. It'll take a few minutes to create everything.

### Inspect created resources

This should create the following resources in AWS for you:

1. A TLS certificate in `Certificate Manager` for your domain
   1. Including `www` as a subject alternative name
2. One hosted zone for your domain in `Route53`, including:
   1. Name server entries, **add these in your registrar for your domain**
   2. A DNS record of type `A` for the apex/root of your domain
   3. A DNS record of type `A` for `www` of your domain
   4. A DNS record of type `CNAME` for validation of your TLS certificate
   5. Optionally, a DNS record of type `CNAME` for an `auth0` custom domain
3. A `S3` bucket to upload content for your domain
   1. And a bucket policy allowing `Cloudfront` CDN to get contents for serving files
4. An `IAM` user to allow upload to the `S3` bucket for your domain, including:
   1. An `IAM Policy` to support content upload via `aws s3 sync`
5. A `Cloundfront` CDN configured to:
   1. Serve requests made to your domain apex and www
   2. Serve content from the `S3` bucket
   3. Redirect HTTP requests to HTTPS, and minimally require TLS 1.2

## Taking it a step further

There is an `output.tf` [file](./output.tf). It controls what is output when `terraform apply` is done.

As is, this file outputs an access key and secret access key. They can be configured in [Github as Secrets](https://docs.github.com/en/actions/reference/encrypted-secrets), and used in a [Github Action](https://docs.github.com/en/actions/learn-github-actions) to build and deploy a SPA to the CDN's S3 bucket like so:

```yaml
name: UI Build and Deploy

# Controls when the action will run. 
on:
  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:    

# A workflow run is made up of one or more jobs that can run sequentially or in parallel
jobs:
  # This workflow contains a single job called "build"
  build:
    # The type of runner that the job will run on
    runs-on: ubuntu-latest

    # Steps represent a sequence of tasks that will be executed as part of the job
    steps:
      # Checks-out your repository under $GITHUB_WORKSPACE, so your job can access it
      - name: Checkout
        uses: actions/checkout@v2
      - name: Install Node
        uses: actions/setup-node@v2.1.5                
      - name: NPM install
        run: npm install
        working-directory: ./ui   
      - name: NPM audit and build
        run: npm run audit && npm run build
        working-directory: ./ui
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      # https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3/sync.html#examples
      - name: Copy files to the test website with the AWS CLI
        working-directory: ./ui/dist/ui   
        run: |
          aws s3 sync . s3://s3-domain-com
```

## My notes

Terraform has providers and modules.

* **Providers** allow you to "do things" to remote systems
  * Manage resources
  * Make API calls
  * AWS and vSphere are a couple examples
* **Modules** allow you to package and reuse patterns for managing resources

AWS modules felt buggy and cumbersome to me, so I stuck with using the provider. As a result, I had to learn about a variety of AWS resources (which the modules likely abstracted away for me).

* The benefit to this is that I have a better understanding of AWS concepts.
* The cost is that I had to write more `TF` code, and in some case determine what my dependencies were when authoring `TF` code.

### AWS references

#### CLI

* <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-creds>
* <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html>
* <https://awscli.amazonaws.com/v2/documentation/api/latest/index.html>

### Terraform references

#### In General

* <https://www.terraform.io/docs/enterprise/before-installing/index.html>
* <https://www.terraform.io/docs/enterprise/system-overview/reliability-availability.html>
* <https://www.terraform.io/docs/language/index.html>
* <https://www.terraform.io/intro/index.html>
* <https://learn.hashicorp.com/collections/terraform/aws-get-started>

#### AWS Provider

* <https://registry.terraform.io/providers/hashicorp/aws/latest>
* <https://registry.terraform.io/providers/hashicorp/aws/latest/docs>
