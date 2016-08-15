# @title Building the SDK for the Browser

# Building the SDK for Use in the Browser

This section explains how you can create your own build of the AWS SDK for
JavaScript. If you are working with the SDK outside of an environment that
enforces CORS in your browser and want access to the full gamut of services
provided by the **AWS SDK for JavaScript**, it is possible to build a custom
copy of the SDK locally by cloning the repository and running the same build
tools used to generate the default hosted version of the SDK. This chapter
outlines the steps to build the SDK on your own with extra services and API
versions.

## Using the SDK Builder

The easiest way to create your own build of the AWS SDK for JavaScript is to
use the SDK builder hosted at
[https://sdk.amazonaws.com/builder/js](https://sdk.amazonaws.com/builder/js).

## Using Command Line Tools

In order to build the SDK using command line tools, you first need to clone
the Git repository containing the SDK source. These instructions assume
you have [Git](http://git-scm.org) and a version of
[Node.js](http://nodejs.org) installed on your machine.

First, clone the repository from GitHub and cd into the directory:

```bash
git clone git://github.com/aws/aws-sdk-js
cd aws-sdk-js
git checkout v2.5.0
```

After you have cloned the repository, you need to download the dependency modules
for both the SDK and build tool:

```bash
npm install
```

You should now be able to build a packaged version of the SDK.

### Building

The builder tool is found in `dist-tools/browser-builder.js`. You can run
this script by typing:

```bash
node dist-tools/browser-builder.js > aws-sdk.js
```

This will build to the file `aws-sdk.js`. By default this package includes
only the services documented in the {file:browser-services.md Working With Services}
chapter. Building custom services is discussed later in this chapter. Note
also that by default, this file is uncompressed.

### Minifying Output

The builder tool can also compress output. To do this, set the `MINIFY`
environment variable like so:

```bash
MINIFY=1 node dist-tools/browser-builder.js > aws-sdk.js
```

### Building Specific Services and API Versions

#### Selecting Services to Build

When building via the builder tool, you can select which services you want to
build into the SDK. To select services, specify the names of the services
delimited by commas as arguments to the tool on the command-line. For example,
to build only Amazon S3 and Amazon EC2, use the following command:

```bash
node dist-tools/browser-builder.js s3,ec2 > aws-sdk-s3-ec2.js
```

#### Selecting API Versions

You can also select specific API versions of services when building
by suffixing the version name after the service identifier. For example, to
build both API versions of Amazon DynamoDB, you could use the following
command:

```bash
node dist-tools/browser-builder.js dynamodb-2011-12-05,dynamodb-2012-08-10
```

The available service identifiers and API versions can be found by viewing the
service-specific configuration files at:
<https://github.com/aws/aws-sdk-js/tree/master/apis>.

#### Building All Services

Finally, you can build **all services** (and API versions) by passing "all"
as a command-line argument:

```bash
node dist-tools/browser-builder.js all > aws-sdk-full.js
```
#### Selecting Custom Services

If you are building the SDK as a dependency in an application using browserify,
you may also need to customize the selected set of services used. To do this,
you can pass the `AWS_SERVICES` environment variable to your browserify
command containing the list of services you want in the same format listed
above:

```sh
$ AWS_SERVICES=ec2,s3,dynamodb browserify index.js > browser-app.js
```

The above bundle will contain the AWS.EC2, AWS.S3, and AWS.DynamoDB services.

## Building the SDK as a Dependency with Browserify

The SDK can also be built as library dependency to any application running
in the browser via [browserify](http://browserify.org). Consider the following
small Node.js application (`index.js`) that uses the SDK:

```js
var AWS = require('aws-sdk');
var s3 = new AWS.S3();
s3.listBuckets(function(err, data) { console.log(err, data); });
```

The above file can be compiled to a browser compatible version with
`browserify` using the following command:

```sh
$ browserify index.js > browser-app.js
```

The application, including all of its dependencies (the SDK), will now be
available in the browser through `browser-app.js`.
