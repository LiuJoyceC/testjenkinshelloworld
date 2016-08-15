helpers = require('../helpers')
AWS = helpers.AWS
Stream = AWS.util.nodeRequire('stream')
Buffer = AWS.util.Buffer

describe 'AWS.S3', ->

  s3 = null
  request = (operation, params) -> s3.makeRequest(operation, params)

  beforeEach (done) ->
    s3 = new AWS.S3(region: undefined)
    s3.clearBucketRegionCache()
    done()

  describe 'dnsCompatibleBucketName', ->

    it 'must be at least 3 characters', ->
      expect(s3.dnsCompatibleBucketName('aa')).to.equal(false)

    it 'must not be longer than 63 characters', ->
      b = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      expect(s3.dnsCompatibleBucketName(b)).to.equal(false)

    it 'must start with a lower-cased letter or number', ->
      expect(s3.dnsCompatibleBucketName('Abc')).to.equal(false)
      expect(s3.dnsCompatibleBucketName('-bc')).to.equal(false)
      expect(s3.dnsCompatibleBucketName('abc')).to.equal(true)

    it 'must end with a lower-cased letter or number', ->
      expect(s3.dnsCompatibleBucketName('abC')).to.equal(false)
      expect(s3.dnsCompatibleBucketName('ab-')).to.equal(false)
      expect(s3.dnsCompatibleBucketName('abc')).to.equal(true)

    it 'may not contain multiple contiguous dots', ->
      expect(s3.dnsCompatibleBucketName('abc.123')).to.equal(true)
      expect(s3.dnsCompatibleBucketName('abc..123')).to.equal(false)

    it 'may only contain letters numbers and dots', ->
      expect(s3.dnsCompatibleBucketName('abc123')).to.equal(true)
      expect(s3.dnsCompatibleBucketName('abc_123')).to.equal(false)

    it 'must not look like an ip address', ->
      expect(s3.dnsCompatibleBucketName('1.2.3.4')).to.equal(false)
      expect(s3.dnsCompatibleBucketName('a.b.c.d')).to.equal(true)

  describe 'constructor', ->
    it 'requires endpoint if s3BucketEndpoint is passed', ->
      expect(-> new AWS.S3(s3BucketEndpoint: true)).to.throw(
        /An endpoint must be provided/)

    it 'does not allow useDualstack and useAccelerateEndpoint to both be true', ->
      expect(-> new AWS.S3(useDualstack: true, useAccelerateEndpoint: true)).to.throw(
        /cannot both be configured to true/)

  describe 'endpoint', ->

    it 'sets hostname to s3.amazonaws.com when region is un-specified', ->
      s3 = new AWS.S3(region: undefined)
      expect(s3.endpoint.hostname).to.equal('s3.amazonaws.com')

    it 'sets hostname to s3.amazonaws.com when region is us-east-1', ->
      s3 = new AWS.S3(region: 'us-east-1')
      expect(s3.endpoint.hostname).to.equal('s3.amazonaws.com')

    it 'sets region to us-east-1 when unspecified', ->
      s3 = new AWS.S3(region: 'us-east-1')
      expect(s3.config.region).to.equal('us-east-1')

    it 'combines the region with s3 in the endpoint using a - instead of .', ->
      s3 = new AWS.S3(region: 'us-west-1')
      expect(s3.endpoint.hostname).to.equal('s3-us-west-1.amazonaws.com')

    it 'sets a region-specific dualstack endpoint when dualstack enabled', ->
      s3 = new AWS.S3(region: 'us-west-1', useDualstack: true)
      expect(s3.endpoint.hostname).to.equal('s3.dualstack.us-west-1.amazonaws.com')
      s3 = new AWS.S3(region: 'us-east-1', useDualstack: true)
      expect(s3.endpoint.hostname).to.equal('s3.dualstack.us-east-1.amazonaws.com')

  describe 'clearing bucket region cache', ->
    beforeEach ->
      s3.bucketRegionCache = a: 'rg-fake-1', b: 'rg-fake-2', c: 'rg-fake-3'

    it 'clears one bucket name', ->
      s3.clearBucketRegionCache 'b'
      expect(s3.bucketRegionCache).to.eql(a: 'rg-fake-1', c: 'rg-fake-3')

    it 'clears a list of bucket names', ->
      s3.clearBucketRegionCache ['a', 'c']
      expect(s3.bucketRegionCache).to.eql(b: 'rg-fake-2')

    it 'clears entire cache', ->
      s3.clearBucketRegionCache()
      expect(s3.bucketRegionCache).to.eql({})

  describe 'getSignerClass', ->
    getVersion = (signer) ->
      if (signer == AWS.Signers.S3)
        return 's3'
      else if (signer == AWS.Signers.V4)
        return 'v4'
      else if (signer == AWS.Signers.V2)
        return 'v2'
    
    describe 'when using presigned requests', ->
      req = null

      beforeEach (done) ->
        req = request('mock')
        helpers.spyOn(req, 'isPresigned').andReturn(true)
        done()

      describe 'will return an s3 (v2) signer when', ->

        it 'user does not specify a signatureVersion for a region that supports v2', (done) ->
          s3 = new AWS.S3(region: 'us-east-1')
          expect(getVersion(s3.getSignerClass(req))).to.equal('s3')
          done()

        it 'user specifies a signatureVersion of s3', (done) ->
          s3 = new AWS.S3(signatureVersion: 's3')
          expect(getVersion(s3.getSignerClass(req))).to.equal('s3')
          done()

        it 'user specifies a signatureVersion of v2', (done) ->
          s3 = new AWS.S3(signatureVersion: 'v2')
          expect(getVersion(s3.getSignerClass(req))).to.equal('s3')
          done()

      describe 'will return a v4 signer when', ->

        it 'user does not specify a signatureVersion for a region that supports only v4', (done) ->
          s3 = new AWS.S3(region: 'eu-central-1')
          expect(getVersion(s3.getSignerClass(req))).to.equal('v4')
          done()

        it 'user specifies a signatureVersion of v4', (done) ->
          s3 = new AWS.S3(signatureVersion: 'v4')
          expect(getVersion(s3.getSignerClass(req))).to.equal('v4')
          done()

    describe 'when not using presigned requests', ->

      describe 'will return an s3 (v2) signer when', ->

        it 'user specifies a signatureVersion of s3', (done) ->
          s3 = new AWS.S3(signatureVersion: 's3')
          expect(getVersion(s3.getSignerClass())).to.equal('s3')
          done()

        it 'user specifies a signatureVersion of v2', (done) ->
          s3 = new AWS.S3(signatureVersion: 'v2')
          expect(getVersion(s3.getSignerClass())).to.equal('s3')
          done()

        it 'user does not specify a signatureVersion and region supports v2', (done) ->
          s3 = new AWS.S3({region: 'us-east-1'})
          expect(getVersion(s3.getSignerClass())).to.equal('s3')
          done()  

      describe 'will return a v4 signer when', ->

        it 'user does not specify a signatureVersion and region only supports v4', (done) ->
          s3 = new AWS.S3({region: 'eu-central-1'})
          expect(getVersion(s3.getSignerClass())).to.equal('v4')
          done()

        it 'user specifies a signatureVersion of v4', (done) ->
          s3 = new AWS.S3(signatureVersion: 'v4')
          expect(getVersion(s3.getSignerClass())).to.equal('v4')
          done()

  describe 'building a request', ->
    build = (operation, params) ->
      request(operation, params).build().httpRequest

    it 'obeys the configuration for s3ForcePathStyle', ->
      config = new AWS.Config(s3ForcePathStyle: true, accessKeyId: 'AKID', secretAccessKey: 'SECRET')
      s3 = new AWS.S3(config)
      expect(s3.config.s3ForcePathStyle).to.equal(true)
      req = build('headObject', {Bucket:'bucket', Key:'key'})
      expect(req.endpoint.hostname).to.equal('s3.amazonaws.com')
      expect(req.path).to.equal('/bucket/key')

    it 'does not enable path style if endpoint is a bucket', ->
      s3 = new AWS.S3(endpoint: 'foo.bar', s3BucketEndpoint: true)
      req = build('listObjects', Bucket: 'bucket')
      expect(req.endpoint.hostname).to.equal('foo.bar')
      expect(req.path).to.equal('/')
      expect(req.virtualHostedBucket).to.equal('bucket')

    it 'allows user override if an endpoint is specified', ->
      s3 = new AWS.S3(endpoint: 'foo.bar', s3ForcePathStyle: true)
      req = build('listObjects', Bucket: 'bucket')
      expect(req.endpoint.hostname).to.equal('foo.bar')
      expect(req.path).to.equal('/bucket')

    it 'does not allow non-bucket operations with s3BucketEndpoint set', ->
      s3 = new AWS.S3(endpoint: 'foo.bar', s3BucketEndpoint: true, paramValidation: true)
      req = s3.listBuckets().build()
      expect(req.response.error.code).to.equal('ConfigError')

    it 'corrects virtual-hosted bucket region on request if bucket region stored in cache', ->
      s3 = new AWS.S3(region: 'us-east-1')
      s3.bucketRegionCache.name = 'us-west-2'
      param = Bucket: 'name'
      req = s3.headBucket(param).build()
      httpRequest = req.httpRequest
      expect(httpRequest.region).to.equal('us-west-2')
      expect(httpRequest.endpoint.hostname).to.equal('name.s3-us-west-2.amazonaws.com')
      expect(httpRequest.headers.Host).to.equal('name.s3-us-west-2.amazonaws.com')
      expect(httpRequest.path).to.equal('/')

    it 'corrects path-style bucket region on request if bucket region stored in cache', ->
      s3 = new AWS.S3(region: 'us-east-1', s3ForcePathStyle: true)
      s3.bucketRegionCache.name = 'us-west-2'
      param = Bucket: 'name'
      req = s3.headBucket(param).build()
      httpRequest = req.httpRequest
      expect(httpRequest.region).to.equal('us-west-2')
      expect(httpRequest.endpoint.hostname).to.equal('s3-us-west-2.amazonaws.com')
      expect(httpRequest.headers.Host).to.equal('s3-us-west-2.amazonaws.com')
      expect(httpRequest.path).to.equal('/name')

    describe 'with useAccelerateEndpoint set to true', ->
      beforeEach ->
        s3 = new AWS.S3(useAccelerateEndpoint: true)

      it 'changes the hostname to use s3-accelerate for dns-comaptible buckets', ->
        req = build('getObject', {Bucket: 'foo', Key: 'bar'})
        expect(req.endpoint.hostname).to.equal('foo.s3-accelerate.amazonaws.com')

      it 'overrides s3BucketEndpoint configuration when s3BucketEndpoint is set', ->
        s3 = new AWS.S3(useAccelerateEndpoint: true, s3BucketEndpoint: true, endpoint: 'foo.region.amazonaws.com')
        req = build('getObject', {Bucket: 'foo', Key: 'baz'})
        expect(req.endpoint.hostname).to.equal('foo.s3-accelerate.amazonaws.com')

      describe 'does not use s3-accelerate', ->
        it 'on dns-incompatible buckets', ->
          req = build('getObject', {Bucket: 'foo.baz', Key: 'bar'})
          expect(req.endpoint.hostname).to.not.contain('s3-accelerate.amazonaws.com')

        it 'on excluded operations', ->
          req = build('listBuckets')
          expect(req.endpoint.hostname).to.not.contain('s3-accelerate.amazonaws.com')
          req = build('createBucket', {Bucket: 'foo'})
          expect(req.endpoint.hostname).to.not.contain('s3-accelerate.amazonaws.com')
          req = build('deleteBucket', {Bucket: 'foo'})
          expect(req.endpoint.hostname).to.not.contain('s3-accelerate.amazonaws.com')


    describe 'uri escaped params', ->
      it 'uri-escapes path and querystring params', ->
        # bucket param ends up as part of the hostname
        params = { Bucket: 'bucket', Key: 'a b c', VersionId: 'a&b' }
        req = build('headObject', params)
        expect(req.path).to.equal('/a%20b%20c?versionId=a%26b')

      it 'does not uri-escape forward slashes in the path', ->
        params = { Bucket: 'bucket', Key: 'k e/y' }
        req = build('headObject', params)
        expect(req.path).to.equal('/k%20e/y')

      it 'ensures a single forward slash exists', ->
        req = build('listObjects', { Bucket: 'bucket' })
        expect(req.path).to.equal('/')

        req = build('listObjects', { Bucket: 'bucket', MaxKeys:123 })
        expect(req.path).to.equal('/?max-keys=123')

    describe 'adding Expect: 100-continue', ->
      if AWS.util.isNode()
        it 'does not add expect header to payloads less than 1MB', ->
          req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024 * 1024 - 1))
          expect(req.headers['Expect']).not.to.exist

        it 'adds expect header to payloads greater than 1MB', ->
          req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024 * 1024 + 1))
          expect(req.headers['Expect']).to.equal('100-continue')

      if AWS.util.isBrowser()
        beforeEach -> helpers.spyOn(AWS.util, 'isBrowser').andReturn(true)

        it 'does not add expect header in the browser', ->
          req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024 * 1024 + 1))
          expect(req.headers['Expect']).not.to.exist

    describe 'with s3DisableBodySigning set to true', ->

      it 'will disable body signing when using signature version 4 and the endpoint uses https', ->
        s3 = new AWS.S3(s3DisableBodySigning: true, signatureVersion: 'v4')
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024*1024*5))
        expect(req.headers['X-Amz-Content-Sha256']).to.equal('UNSIGNED-PAYLOAD')

      it 'will compute contentMD5', ->
        s3 = new AWS.S3(s3DisableBodySigning: true, signatureVersion: 'v4')
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024*1024*5))
        expect(req.headers['Content-MD5']).to.equal('XzY+DlipXwbL6bvGYsXftg==')

      it 'will not disable body signing when the endpoint is not https', ->
        s3 = new AWS.S3(s3DisableBodySigning: true, signatureVersion: 'v4', sslEnabled: false)
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024*1024*5))
        expect(req.headers['X-Amz-Content-Sha256']).to.exist
        expect(req.headers['X-Amz-Content-Sha256']).to.not.equal('UNSIGNED-PAYLOAD')

      it 'will have no effect when sigv2 signing is used', ->
        s3 = new AWS.S3(s3DisableBodySigning: true, signatureVersion: 's3', sslEnabled: true)
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024*1024*5))
        expect(req.headers['X-Amz-Content-Sha256']).to.not.exist

    describe 'with s3DisableBodySigning set to false', ->

      it 'will sign the body when sigv4 is used', ->
        s3 = new AWS.S3(s3DisableBodySigning: false, signatureVersion: 'v4')
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024*1024*5))
        expect(req.headers['X-Amz-Content-Sha256']).to.exist
        expect(req.headers['X-Amz-Cotnent-Sha256']).to.not.equal('UNSIGNED-PAYLOAD')

      it 'will have no effect when sigv2 signing is used', ->
        s3 = new AWS.S3(s3DisableBodySigning: false, signatureVersion: 's3', sslEnabled: true)
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer(1024*1024*5))
        expect(req.headers['X-Amz-Content-Sha256']).to.not.exist


    describe 'adding Content-Type', ->
      beforeEach -> helpers.spyOn(AWS.util, 'isBrowser').andReturn(true)

      it 'adds default content-type when not supplied', ->
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: 'body')
        expect(req.headers['Content-Type']).to.equal('application/octet-stream; charset=UTF-8')

      it 'does not add content-type for GET/HEAD requests', ->
        req = build('getObject', Bucket: 'bucket', Key: 'key')
        expect(req.headers['Content-Type']).not.to.exist

        req = build('headObject', Bucket: 'bucket', Key: 'key')
        expect(req.headers['Content-Type']).not.to.exist

      it 'adds charset to existing content-type if not supplied', ->
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: 'body', ContentType: 'text/html')
        expect(req.headers['Content-Type']).to.equal('text/html; charset=UTF-8')

      it 'normalized charset to uppercase', ->
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: 'body', ContentType: 'text/html; charset=utf-8')
        expect(req.headers['Content-Type']).to.equal('text/html; charset=UTF-8')

      it 'does not add charset to non-string data', ->
        req = build('putObject', Bucket: 'bucket', Key: 'key', Body: new Buffer('body'), ContentType: 'image/png')
        expect(req.headers['Content-Type']).to.equal('image/png')

    describe 'virtual-hosted vs path-style bucket requests', ->

      describe 'HTTPS', ->

        beforeEach ->
          s3 = new AWS.S3(sslEnabled: true, region: undefined)

        it 'puts dns-compat bucket names in the hostname', ->
          req = build('headObject', {Bucket:'bucket-name',Key:'abc'})
          expect(req.method).to.equal('HEAD')
          expect(req.endpoint.hostname).to.equal('bucket-name.s3.amazonaws.com')
          expect(req.path).to.equal('/abc')

        it 'ensures the path contains / at a minimum when moving bucket', ->
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).to.equal('bucket-name.s3.amazonaws.com')
          expect(req.path).to.equal('/')

        it 'puts dns-compat bucket names in path if they contain a dot', ->
          req = build('listObjects', {Bucket:'bucket.name'})
          expect(req.endpoint.hostname).to.equal('s3.amazonaws.com')
          expect(req.path).to.equal('/bucket.name')

        it 'puts dns-compat bucket names in path if configured to do so', ->
          s3 = new AWS.S3(sslEnabled: true, s3ForcePathStyle: true, region: undefined)
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).to.equal('s3.amazonaws.com')
          expect(req.path).to.equal('/bucket-name')

        it 'puts dns-incompat bucket names in path', ->
          req = build('listObjects', {Bucket:'bucket_name'})
          expect(req.endpoint.hostname).to.equal('s3.amazonaws.com')
          expect(req.path).to.equal('/bucket_name')

      describe 'HTTP', ->

        beforeEach ->
          s3 = new AWS.S3(sslEnabled: false, region: undefined)

        it 'puts dns-compat bucket names in the hostname', ->
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).to.equal('bucket-name.s3.amazonaws.com')
          expect(req.path).to.equal('/')

        it 'puts dns-compat bucket names in the hostname if they contain a dot', ->
          req = build('listObjects', {Bucket:'bucket.name'})
          expect(req.endpoint.hostname).to.equal('bucket.name.s3.amazonaws.com')
          expect(req.path).to.equal('/')

        it 'puts dns-incompat bucket names in path', ->
          req = build('listObjects', {Bucket:'bucket_name'})
          expect(req.endpoint.hostname).to.equal('s3.amazonaws.com')
          expect(req.path).to.equal('/bucket_name')

      describe 'HTTPS dualstack', ->

        beforeEach ->
          s3 = new AWS.S3(sslEnabled: true, region: undefined, useDualstack: true)

        it 'puts dns-compat bucket names in the hostname', ->
          req = build('headObject', {Bucket:'bucket-name',Key:'abc'})
          expect(req.method).to.equal('HEAD')
          expect(req.endpoint.hostname).to.equal('bucket-name.s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/abc')

        it 'ensures the path contains / at a minimum when moving bucket', ->
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).to.equal('bucket-name.s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/')

        it 'puts dns-compat bucket names in path if they contain a dot', ->
          req = build('listObjects', {Bucket:'bucket.name'})
          expect(req.endpoint.hostname).to.equal('s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/bucket.name')

        it 'puts dns-compat bucket names in path if configured to do so', ->
          s3 = new AWS.S3(sslEnabled: true, s3ForcePathStyle: true, region: undefined, useDualstack: true)
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).to.equal('s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/bucket-name')

        it 'puts dns-incompat bucket names in path', ->
          req = build('listObjects', {Bucket:'bucket_name'})
          expect(req.endpoint.hostname).to.equal('s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/bucket_name')

      describe 'HTTP dualstack', ->

        beforeEach ->
          s3 = new AWS.S3(sslEnabled: false, region: undefined, useDualstack: true)

        it 'puts dns-compat bucket names in the hostname', ->
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).to.equal('bucket-name.s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/')

        it 'puts dns-compat bucket names in the hostname if they contain a dot', ->
          req = build('listObjects', {Bucket:'bucket.name'})
          expect(req.endpoint.hostname).to.equal('bucket.name.s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/')

        it 'puts dns-incompat bucket names in path', ->
          req = build('listObjects', {Bucket:'bucket_name'})
          expect(req.endpoint.hostname).to.equal('s3.dualstack.us-east-1.amazonaws.com')
          expect(req.path).to.equal('/bucket_name')

  describe 'SSE support', ->
    beforeEach -> s3 = new AWS.S3

    it 'fails if the scheme is not HTTPS: when SSECustomerKey is provided', ->
      req = s3.putObject
        Bucket: 'bucket', Key: 'key', Body: 'object'
        SSECustomerKey: 'sse-key', SSECustomerAlgorithm: 'AES256'
      req.httpRequest.endpoint.protocol = 'http:'
      req.build()
      expect(req.response.error.code).to.equal('ConfigError')

    it 'fails if the scheme is not HTTPS: when CopySourceSSECustomerKey is provided', ->
      req = s3.putObject
        Bucket: 'bucket', Key: 'key', Body: 'object'
        CopySourceSSECustomerKey: 'sse-key', CopySourceSSECustomerAlgorithm: 'AES256'
      req.httpRequest.endpoint.protocol = 'http:'
      req.build()
      expect(req.response.error.code).to.equal('ConfigError')

    describe 'SSECustomerKey', ->
      it 'encodes strings keys and fills in MD5', ->
        req = s3.putObject
          Bucket: 'bucket', Key: 'key', Body: 'data'
          SSECustomerKey: 'KEY', SSECustomerAlgorithm: 'AES256'
        req.build()
        expect(req.httpRequest.headers['x-amz-server-side-encryption-customer-key']).
          to.equal('S0VZ')
        expect(req.httpRequest.headers['x-amz-server-side-encryption-customer-key-MD5']).
          to.equal('O1lJ4MJrh3Z6R1Kidt6VcA==')

      it 'encodes blob keys and fills in MD5', ->
        req = s3.putObject
          Bucket: 'bucket', Key: 'key', Body: 'data'
          SSECustomerKey: new AWS.util.Buffer('098f6bcd4621d373cade4e832627b4f6', 'hex')
          SSECustomerAlgorithm: 'AES256'
        req.build()
        expect(req.httpRequest.headers['x-amz-server-side-encryption-customer-key']).
          to.equal('CY9rzUYh03PK3k6DJie09g==')
        expect(req.httpRequest.headers['x-amz-server-side-encryption-customer-key-MD5']).
          to.equal('YM1UqSjLvLtue1WVurRqng==')

    describe 'CopySourceSSECustomerKey', ->
      it 'encodes string keys and fills in MD5', ->
        req = s3.copyObject
          Bucket: 'bucket', Key: 'key', CopySource: 'bucket/oldkey', Body: 'data'
          CopySourceSSECustomerKey: 'KEY', CopySourceSSECustomerAlgorithm: 'AES256'
        req.build()
        expect(req.httpRequest.headers['x-amz-copy-source-server-side-encryption-customer-key']).
          to.equal('S0VZ')
        expect(req.httpRequest.headers['x-amz-copy-source-server-side-encryption-customer-key-MD5']).
          to.equal('O1lJ4MJrh3Z6R1Kidt6VcA==')

      it 'encodes blob keys and fills in MD5', ->
        req = s3.copyObject
          Bucket: 'bucket', Key: 'key', CopySource: 'bucket/oldkey', Body: 'data'
          CopySourceSSECustomerKey: new AWS.util.Buffer('098f6bcd4621d373cade4e832627b4f6', 'hex')
          CopySourceSSECustomerAlgorithm: 'AES256'
        req.build()
        expect(req.httpRequest.headers['x-amz-copy-source-server-side-encryption-customer-key']).
          to.equal('CY9rzUYh03PK3k6DJie09g==')
        expect(req.httpRequest.headers['x-amz-copy-source-server-side-encryption-customer-key-MD5']).
          to.equal('YM1UqSjLvLtue1WVurRqng==')

  describe 'retry behavior', ->
    it 'retries RequestTimeout errors', ->
      s3.config.maxRetries = 3
      helpers.mockHttpResponse 400, {},
        '<xml><Code>RequestTimeout</Code><Message>message</Message></xml>'
      s3.putObject (err, data) ->
        expect(@retryCount).to.equal(s3.config.maxRetries)

  # Managed Upload integration point
  describe 'upload', ->
    it 'accepts parameters in upload() call', ->
      helpers.mockResponses [ { data: { ETag: 'ETAG' } } ]
      done = false
      s3.upload({Bucket: 'bucket', Key: 'key', Body: 'body'}, -> done = true)
      expect(done).to.equal(true)

    it 'accepts options as a second parameter', ->
      helpers.mockResponses [ { data: { ETag: 'ETAG' } } ]
      upload = s3.upload({Bucket: 'bucket', Key: 'key', Body: 'body'}, {queueSize: 2}, ->)
      expect(upload.queueSize).to.equal(2)

    it 'does not send if no callback is supplied', ->
      s3.upload(Bucket: 'bucket', Key: 'key', Body: 'body')

  describe 'extractData', ->
    it 'caches bucket region if found in header', ->
      req = request('operation', {Bucket: 'name'})
      resp = new AWS.Response(req)
      resp.httpResponse.headers = 'x-amz-bucket-region': 'rg-fake-1'
      req.emit('extractData', [resp])
      expect(s3.bucketRegionCache.name).to.equal('rg-fake-1')

  # S3 returns a handful of errors without xml bodies (to match the
  # http spec) these tests ensure we give meaningful codes/messages for these.
  describe 'errors with no XML body', ->
    regionReqOperation = if AWS.util.isNode() then 'headBucket' else 'listObjects'
    maxKeysParam = if regionReqOperation == 'listObjects' then 0 else undefined

    extractError = (statusCode, body, addHeaders, req) ->
      if !req
        req = request('operation')
      resp = new AWS.Response(req)
      resp.httpResponse.body = new Buffer(body || '')
      resp.httpResponse.statusCode = statusCode
      resp.httpResponse.headers = {'x-amz-request-id': 'RequestId', 'x-amz-id-2': 'ExtendedRequestId'}
      for header, value of addHeaders
        resp.httpResponse.headers[header] = value
      req.emit('extractError', [resp])
      resp.error

    it 'handles 304 errors', ->
      error = extractError(304)
      expect(error.code).to.equal('NotModified')
      expect(error.message).to.equal(null)

    it 'handles 400 errors', ->
      error = extractError(400)
      expect(error.code).to.equal('BadRequest')
      expect(error.message).to.equal(null)

    it 'handles 403 errors', ->
      error = extractError(403)
      expect(error.code).to.equal('Forbidden')
      expect(error.message).to.equal(null)

    it 'handles 404 errors', ->
      error = extractError(404)
      expect(error.code).to.equal('NotFound')
      expect(error.message).to.equal(null)

    it 'extracts the region from body and takes precedence over cache', ->
      s3.bucketRegionCache.name = 'us-west-2'
      req = request('operation', {Bucket: 'name'})
      body = """
        <Error>
          <Code>InvalidArgument</Code>
          <Message>Provided param is bad</Message>
          <Region>eu-west-1</Region>
        </Error>
        """
      error = extractError(400, body, {}, req)
      expect(error.region).to.equal('eu-west-1')
      expect(s3.bucketRegionCache.name).to.equal('eu-west-1')

    it 'extracts the region from header and takes precedence over body and cache', ->
      s3.bucketRegionCache.name = 'us-west-2'
      req = request('operation', {Bucket: 'name'})
      body = """
        <Error>
          <Code>InvalidArgument</Code>
          <Message>Provided param is bad</Message>
          <Region>eu-west-1</Region>
        </Error>
        """
      headers = 'x-amz-bucket-region': 'us-east-1'
      error = extractError(400, body, headers, req)
      expect(error.region).to.equal('us-east-1')
      expect(s3.bucketRegionCache.name).to.equal('us-east-1')

    it 'uses cache if region not extracted from body or header', ->
      s3.bucketRegionCache.name = 'us-west-2'
      req = request('operation', {Bucket: 'name'})
      body = """
        <Error>
          <Code>InvalidArgument</Code>
          <Message>Provided param is bad</Message>
        </Error>
        """
      error = extractError(400, body, {}, req)
      expect(error.region).to.equal('us-west-2')
      expect(s3.bucketRegionCache.name).to.equal('us-west-2')

    it 'does not use cache if not different from current region', ->
      s3.bucketRegionCache.name = 'us-west-2'
      req = request('operation', {Bucket: 'name'})
      req.httpRequest.region = 'us-west-2'
      body = """
        <Error>
          <Code>InvalidArgument</Code>
          <Message>Provided param is bad</Message>
        </Error>
        """
      error = extractError(400, body)
      expect(error.region).to.not.exist
      expect(s3.bucketRegionCache.name).to.equal('us-west-2')

    it 'does not make async request for bucket region if error.region is set', ->
      regionReq = send: (fn) ->
        fn()
      spy = helpers.spyOn(s3, regionReqOperation).andReturn(regionReq)
      req = request('operation', {Bucket: 'name'})
      body = """
        <Error>
          <Code>PermanentRedirect</Code>
          <Message>Message</Message>
        </Error>
        """
      headers = 'x-amz-bucket-region': 'us-east-1'
      error = extractError(301, body, headers, req)
      expect(error.region).to.exist
      expect(spy.calls.length).to.equal(0)
      expect(regionReq._requestRegionForBucket).to.not.exist

    it 'makes async request for bucket region if error.region not set for a region redirect error code', ->
      regionReq = send: (fn) ->
        fn()
      spy = helpers.spyOn(s3, regionReqOperation).andReturn(regionReq)
      params = Bucket: 'name'
      req = request('operation', params)
      body = """
        <Error>
          <Code>PermanentRedirect</Code>
          <Message>Message</Message>
        </Error>
        """
      error = extractError(301, body, {}, req)
      expect(error.region).to.not.exist
      expect(spy.calls.length).to.equal(1)
      expect(spy.calls[0].arguments[0].Bucket).to.equal('name')
      expect(spy.calls[0].arguments[0].MaxKeys).to.equal(maxKeysParam)
      expect(regionReq._requestRegionForBucket).to.exist

    it 'does not make request for bucket region if error code is not a region redirect code', ->
      regionReq = send: (fn) ->
        fn()
      spy = helpers.spyOn(s3, regionReqOperation).andReturn(regionReq)
      req = request('operation', {Bucket: 'name'})
      body = """
        <Error>
          <Code>InvalidCode</Code>
          <Message>Message</Message>
        </Error>
        """
      error = extractError(301, body, {}, req)
      expect(error.region).to.not.exist
      expect(spy.calls.length).to.equal(0)
      expect(regionReq._requestRegionForBucket).to.not.exist

    it 'updates error.region if async request adds region to cache', ->
      regionReq = send: (fn) ->
        s3.bucketRegionCache.name = 'us-west-2'
        fn()
      spy = helpers.spyOn(s3, regionReqOperation).andReturn(regionReq)
      req = request('operation', {Bucket: 'name'})
      body = """
        <Error>
          <Code>PermanentRedirect</Code>
          <Message>Message</Message>
        </Error>
        """
      error = extractError(301, body, {}, req)
      expect(spy.calls.length).to.equal(1)
      expect(spy.calls[0].arguments[0].Bucket).to.equal('name')
      expect(spy.calls[0].arguments[0].MaxKeys).to.equal(maxKeysParam)
      expect(error.region).to.equal('us-west-2')

    it 'extracts the request ids', ->
      error = extractError(400)
      expect(error.requestId).to.equal('RequestId')
      expect(error.extendedRequestId).to.equal('ExtendedRequestId')

    it 'misc errors not known to return an empty body', ->
      error = extractError(412) # made up
      expect(error.code).to.equal(412)
      expect(error.message).to.equal(null)

    it 'uses canned errors only when the body is empty', ->
      body = """
      <xml>
        <Code>ErrorCode</Code>
        <Message>ErrorMessage</Message>
      </xml>
      """
      error = extractError(403, body)
      expect(error.code).to.equal('ErrorCode')
      expect(error.message).to.equal('ErrorMessage')

  describe 'retryableError', ->

    it 'should retry on authorization header with updated region', ->
      err = {code: 'AuthorizationHeaderMalformed', statusCode:400, region: 'eu-west-1'}
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3.amazonaws.com')

    it 'should retry on bad request with updated region', ->
      err = {code: 'BadRequest', statusCode:400, region: 'eu-west-1'}
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3.amazonaws.com')

    it 'should retry on permanent redirect with updated region and endpoint', ->
      err = {code: 'PermanentRedirect', statusCode:301, region: 'eu-west-1'}
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3-eu-west-1.amazonaws.com')

    it 'should retry on error code 301 with updated region and endpoint', ->
      err = {code: 301, statusCode:301, region: 'eu-west-1'}
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3-eu-west-1.amazonaws.com')

    it 'should retry with updated region but not endpoint if non-S3 url endpoint is specified', ->
      err = {code: 'PermanentRedirect', statusCode:301, region: 'eu-west-1'}
      s3 = new AWS.S3(endpoint: 'https://fake-custom-url.com', s3BucketEndpoint: true)
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('fake-custom-url.com')

    it 'should retry with updated endpoint if S3 url endpoint is specified', ->
      err = {code: 'PermanentRedirect', statusCode:301, region: 'eu-west-1'}
      s3 = new AWS.S3(endpoint: 'https://name.s3-us-west-2.amazonaws.com', s3BucketEndpoint: true)
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3-eu-west-1.amazonaws.com')

    it 'should retry with updated region but not endpoint if accelerate endpoint is used', ->
      err = {code: 'PermanentRedirect', statusCode:301, region: 'eu-west-1'}
      s3 = new AWS.S3(useAccelerateEndpoint: true)
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3-accelerate.amazonaws.com')

    it 'should retry with updated endpoint if dualstack endpoint is used', ->
      err = {code: 'PermanentRedirect', statusCode:301, region: 'eu-west-1'}
      s3 = new AWS.S3(useDualstack: true)
      req = request('operation', {Bucket: 'name'})
      req.build()
      retryable = s3.retryableError(err, req)
      expect(retryable).to.equal(true)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3.dualstack.eu-west-1.amazonaws.com')

    it 'should not retry on requests for bucket region once region is obtained', ->
      err = {code: 'PermanentRedirect', statusCode:301, region: 'eu-west-1'}
      req = request('operation', {Bucket: 'name'})
      req._requestRegionForBucket = 'name'
      retryable = []
      retryable.push s3.retryableError(err, req)
      s3.bucketRegionCache.name = 'eu-west-1'
      retryable.push s3.retryableError(err, req)
      expect(retryable).to.eql([true, false])

  describe 'browser NetworkingError due to wrong region', ->
    done = ->
    spy = null
    regionReq = null

    callNetworkingErrorListener = (req) ->
      if !req
        req = request('operation', {Bucket: 'name'})
      if req._asm.currentState == 'validate'
        req.build()
      resp = new AWS.Response(req)
      resp.error = code: 'NetworkingError'
      s3.reqRegionForNetworkingError(resp, done)
      req

    beforeEach ->
      s3 = new AWS.S3(region: 'us-west-2')
      regionReq = request('operation', {Bucket: 'name'})
      regionReq.send = (fn) ->
        fn()
      helpers.spyOn(AWS.util, 'isBrowser').andReturn(true)
      spy = helpers.spyOn(s3, 'listObjects').andReturn(regionReq)

    it 'updates region to us-east-1 if bucket name not DNS compatible', ->
      req = request('operation', {Bucket: 'name!'})
      callNetworkingErrorListener(req)
      expect(req.httpRequest.region).to.equal('us-east-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('s3.amazonaws.com')
      expect(s3.bucketRegionCache['name!']).to.equal('us-east-1')
      expect(spy.calls.length).to.equal(0)

    it 'updates region if cached and not current region', ->
      req = request('operation', {Bucket: 'name'})
      req.build()
      s3.bucketRegionCache.name = 'eu-west-1'
      callNetworkingErrorListener(req)
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3-eu-west-1.amazonaws.com')
      expect(spy.calls.length).to.equal(0)

    it 'makes async request in us-east-1 if not in cache', ->
      regionReq.send = (fn) ->
        s3.bucketRegionCache.name = 'eu-west-1'
        fn()
      req = callNetworkingErrorListener()
      expect(spy.calls.length).to.equal(1)
      expect(regionReq.httpRequest.region).to.equal('us-east-1')
      expect(regionReq.httpRequest.endpoint.hostname).to.equal('name.s3.amazonaws.com')
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3-eu-west-1.amazonaws.com')

    it 'makes async request in us-east-1 if cached region matches current region', ->
      s3.bucketRegionCache.name = 'us-west-2'
      regionReq.send = (fn) ->
        s3.bucketRegionCache.name = 'eu-west-1'
        fn()
      req = callNetworkingErrorListener()
      expect(spy.calls.length).to.equal(1)  
      expect(regionReq.httpRequest.region).to.equal('us-east-1')
      expect(regionReq.httpRequest.endpoint.hostname).to.equal('name.s3.amazonaws.com')
      expect(req.httpRequest.region).to.equal('eu-west-1')
      expect(req.httpRequest.endpoint.hostname).to.equal('name.s3-eu-west-1.amazonaws.com')

    it 'does not update region if path-style bucket is dns-compliant and not in cache', ->
      s3.config.s3ForcePathStyle = true
      regionReq.send = (fn) ->
        s3.bucketRegionCache.name = 'eu-west-1'
        fn()
      req = callNetworkingErrorListener()
      expect(spy.calls.length).to.equal(0)
      expect(req.httpRequest.region).to.equal('us-west-2')
      expect(req.httpRequest.endpoint.hostname).to.equal('s3-us-west-2.amazonaws.com')

  # tests from this point on are "special cases" for specific aws operations

  describe 'getBucketAcl', ->
    it 'correctly parses the ACL XML document', ->
      headers = { 'x-amz-request-id' : 'request-id' }
      body =
        """
        <AccessControlPolicy xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <AccessControlList>
            <Grant>
              <Grantee xsi:type="CanonicalUser" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <DisplayName>aws-sdk</DisplayName>
                <ID>id</ID>
              </Grantee>
              <Permission>FULL_CONTROL</Permission>
            </Grant>
            <Grant>
              <Grantee xsi:type="Group" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <URI>uri</URI>
              </Grantee>
              <Permission>READ</Permission>
            </Grant>
          </AccessControlList>
          <Owner>
            <DisplayName>aws-sdk</DisplayName>
            <ID>id</ID>
          </Owner>
        </AccessControlPolicy>
        """
      helpers.mockHttpResponse 200, headers, body
      s3.getBucketAcl (error, data) ->
        expect(error).to.equal(null)
        expect(data).to.eql({
          Owner:
            DisplayName: 'aws-sdk',
            ID: 'id'
          Grants: [
            {
              Permission: 'FULL_CONTROL'
              Grantee:
                Type: 'CanonicalUser'
                DisplayName: 'aws-sdk'
                ID: 'id'
            },
            {
              Permission : 'READ'
              Grantee:
                Type: 'Group'
                URI: 'uri'
            }
          ]
        })

  describe 'putBucketAcl', ->
    it 'correctly builds the ACL XML document', ->
      xml =
        """
        <AccessControlPolicy xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <AccessControlList>
            <Grant>
              <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="CanonicalUser">
                <DisplayName>aws-sdk</DisplayName>
                <ID>id</ID>
              </Grantee>
              <Permission>FULL_CONTROL</Permission>
            </Grant>
            <Grant>
              <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Group">
                <URI>uri</URI>
              </Grantee>
              <Permission>READ</Permission>
            </Grant>
          </AccessControlList>
          <Owner>
            <DisplayName>aws-sdk</DisplayName>
            <ID>id</ID>
          </Owner>
        </AccessControlPolicy>
        """
      helpers.mockHttpResponse 200, {}, ''
      params =
        AccessControlPolicy:
          Owner:
            DisplayName: 'aws-sdk',
            ID: 'id'
          Grants: [
            {
              Permission: 'FULL_CONTROL'
              Grantee:
                Type: 'CanonicalUser',
                DisplayName: 'aws-sdk'
                ID: 'id'
            },
            {
              Permission : 'READ'
              Grantee:
                Type: 'Group',
                URI: 'uri'
            }
          ]
      s3.putBucketAcl params, (err, data) ->
        helpers.matchXML(this.request.httpRequest.body, xml)

  describe 'completeMultipartUpload', ->

    it 'returns data when the resp is 200 with valid response', ->
      headers =
        'x-amz-id-2': 'Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg=='
        'x-amz-request-id': '656c76696e6727732072657175657374'
      body =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Location>http://Example-Bucket.s3.amazonaws.com/Example-Object</Location>
          <Bucket>Example-Bucket</Bucket>
          <Key>Example-Object</Key>
          <ETag>"3858f62230ac3c915f300c664312c11f-9"</ETag>
        </CompleteMultipartUploadResult>
        """

      helpers.mockHttpResponse 200, headers, body
      s3.completeMultipartUpload (error, data) ->
        expect(error).to.equal(null)
        expect(data).to.eql({
          Location: 'http://Example-Bucket.s3.amazonaws.com/Example-Object'
          Bucket: 'Example-Bucket'
          Key: 'Example-Object'
          ETag: '"3858f62230ac3c915f300c664312c11f-9"'
        })
        expect(this.requestId).to.equal('656c76696e6727732072657175657374')

    it 'returns an error when the resp is 200 with an error xml document', ->
      body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <Error>
        <Code>InternalError</Code>
        <Message>We encountered an internal error. Please try again.</Message>
        <RequestId>656c76696e6727732072657175657374</RequestId>
        <HostId>Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg==</HostId>
      </Error>
      """

      helpers.mockHttpResponse 200, {}, body
      s3.completeMultipartUpload (error, data) ->
        expect(error ).to.be.instanceOf(Error)
        expect(error.code).to.equal('InternalError')
        expect(error.message).to.equal('We encountered an internal error. Please try again.')
        expect(error.statusCode).to.equal(200)
        expect(error.retryable).to.equal(true)
        expect(data).to.equal(null)

  describe 'copyObject', ->

    it 'returns data when the resp is 200 with valid response', ->
      headers =
        'x-amz-id-2': 'Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg=='
        'x-amz-request-id': '656c76696e6727732072657175657374'
      body =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <CopyObjectResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Location>http://Example-Bucket.s3.amazonaws.com/Example-Object</Location>
          <Bucket>Example-Bucket</Bucket>
          <Key>Example-Object</Key>
          <ETag>"3858f62230ac3c915f300c664312c11f-9"</ETag>
        </CopyObjectResult>
        """

      helpers.mockHttpResponse 200, headers, body
      s3.copyObject (error, data) ->
        expect(error).to.equal(null)
        expect(data).to.eql({
          CopyObjectResult: {
            ETag: '"3858f62230ac3c915f300c664312c11f-9"'
          }
        })
        expect(this.requestId).to.equal('656c76696e6727732072657175657374')

    it 'returns an error when the resp is 200 with an error xml document', ->
      body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <Error>
        <Code>InternalError</Code>
        <Message>We encountered an internal error. Please try again.</Message>
        <RequestId>656c76696e6727732072657175657374</RequestId>
        <HostId>Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg==</HostId>
      </Error>
      """

      helpers.mockHttpResponse 200, {}, body
      s3.copyObject (error, data) ->
        expect(error ).to.be.instanceOf(Error)
        expect(error.code).to.equal('InternalError')
        expect(error.message).to.equal('We encountered an internal error. Please try again.')
        expect(error.statusCode).to.equal(200)
        expect(error.retryable).to.equal(true)
        expect(data).to.equal(null)

  describe 'uploadPartCopy', ->

    it 'returns data when the resp is 200 with valid response', ->
      headers =
        'x-amz-id-2': 'Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg=='
        'x-amz-request-id': '656c76696e6727732072657175657374'
      body =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <CopyPartResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Location>http://Example-Bucket.s3.amazonaws.com/Example-Object</Location>
          <Bucket>Example-Bucket</Bucket>
          <Key>Example-Object</Key>
          <ETag>"3858f62230ac3c915f300c664312c11f-9"</ETag>
        </CopyPartResult>
        """

      helpers.mockHttpResponse 200, headers, body
      s3.uploadPartCopy {Bucket: 'bucket', Key: 'key', CopySource: 'bucket/key'}, (error, data) ->
        expect(error).to.equal(null)
        expect(data).to.eql({
          CopyPartResult: {
            ETag: '"3858f62230ac3c915f300c664312c11f-9"'
          }
        })
        expect(this.requestId).to.equal('656c76696e6727732072657175657374')

    it 'returns an error when the resp is 200 with an error xml document', ->
      body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <Error>
        <Code>InternalError</Code>
        <Message>We encountered an internal error. Please try again.</Message>
        <RequestId>656c76696e6727732072657175657374</RequestId>
        <HostId>Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg==</HostId>
      </Error>
      """

      helpers.mockHttpResponse 200, {}, body
      s3.uploadPartCopy (error, data) ->
        expect(error ).to.be.instanceOf(Error)
        expect(error.code).to.equal('InternalError')
        expect(error.message).to.equal('We encountered an internal error. Please try again.')
        expect(error.statusCode).to.equal(200)
        expect(error.retryable).to.equal(true)
        expect(data).to.equal(null)

  describe 'getBucketLocation', ->

    it 'returns empty string for the location constraint when not present', ->
      body = '<?xml version="1.0" encoding="UTF-8"?>\n<LocationConstraint xmlns="http://s3.amazonaws.com/doc/2006-03-01/"/>'
      helpers.mockHttpResponse 200, {}, body
      s3.getBucketLocation (error, data) ->
        expect(error).to.equal(null)
        expect(data).to.eql({LocationConstraint: ''})

    it 'parses the location constraint from the root xml', ->
      headers = { 'x-amz-request-id': 'abcxyz' }
      body = '<?xml version="1.0" encoding="UTF-8"?>\n<LocationConstraint xmlns="http://s3.amazonaws.com/doc/2006-03-01/">EU</LocationConstraint>'
      helpers.mockHttpResponse 200, headers, body
      s3.getBucketLocation (error, data) ->
        expect(error).to.equal(null)
        expect(data).to.eql(LocationConstraint: 'EU')
        expect(this.requestId).to.equal('abcxyz')

  describe 'createBucket', ->
    it 'auto-populates the LocationConstraint based on the region', ->
      loc = null
      s3 = new AWS.S3(region:'eu-west-1')
      s3.makeRequest = (op, params) ->
        expect(params).to['be'].a('object')
        loc = params.CreateBucketConfiguration.LocationConstraint
      s3.createBucket(Bucket:'name')
      expect(loc).to.equal('eu-west-1')

    it 'auto-populates the LocationConstraint based on the region when using bound params', ->
      loc = null
      s3 = new AWS.S3(region:'eu-west-1', Bucket:'name')
      s3.makeRequest = (op, params) ->
        expect(params).to['be'].a('object')
        loc = params.CreateBucketConfiguration.LocationConstraint
      s3.createBucket(AWS.util.fn.noop)
      expect(loc).to.equal('eu-west-1')

    it 'auto-populates the LocationConstraint based on the region when using invalid params', ->
      loc = null
      s3 = new AWS.S3(region:'eu-west-1', Bucket:'name')
      s3.makeRequest = (op, params) ->
        expect(params).to['be'].a('object')
        loc = params.CreateBucketConfiguration.LocationConstraint
      s3.createBucket(null)
      expect(loc).to.equal('eu-west-1')
      s3.createBucket(undefined)
      expect(loc).to.equal('eu-west-1')

    it 'auto-populates the LocationConstraint based on the region when using invalid params and a valid callback', ->
      loc = null
      s3 = new AWS.S3(region:'eu-west-1', Bucket:'name')
      s3.makeRequest = (op, params, cb) ->
        expect(params).to['be'].a('object')
        loc = params.CreateBucketConfiguration.LocationConstraint
        cb() if typeof cb == 'function'
      called = 0
      s3.createBucket(undefined, () -> called = 1)
      expect(loc).to.equal('eu-west-1')
      expect(called).to.equal(1)

    it 'caches bucket region based on LocationConstraint upon successful response', ->
      s3 = new AWS.S3()
      params = Bucket: 'name', CreateBucketConfiguration: LocationConstraint: 'rg-fake-1'
      helpers.mockHttpResponse 200, {}, ''
      s3.createBucket params, ->
        expect(s3.bucketRegionCache.name).to.equal('rg-fake-1')

    it 'caches bucket region without LocationConstraint upon successful response', ->
      s3 = new AWS.S3(region: 'us-east-1')
      params = Bucket: 'name'
      helpers.mockHttpResponse 200, {}, ''
      s3.createBucket params, ->
        expect(params.CreateBucketConfiguration).to.not.exist
        expect(s3.bucketRegionCache.name).to.equal('us-east-1')

    it 'caches bucket region with LocationConstraint "EU" upon successful response', ->
      s3 = new AWS.S3()
      params = Bucket: 'name', CreateBucketConfiguration: LocationConstraint: 'EU'
      helpers.mockHttpResponse 200, {}, ''
      s3.createBucket params, ->
        expect(s3.bucketRegionCache.name).to.equal('eu-west-1')

  describe 'deleteBucket', ->
    it 'removes bucket from region cache on successful response', ->
      s3 = new AWS.S3()
      params = Bucket: 'name'
      s3.bucketRegionCache.name = 'rg-fake-1'
      helpers.mockHttpResponse 204, {}, '' 
      s3.deleteBucket params, ->
        expect(s3.bucketRegionCache.name).to.not.exist

  AWS.util.each AWS.S3.prototype.computableChecksumOperations, (operation) ->
    describe operation, ->
      it 'forces Content-MD5 header parameter', ->
        req = s3[operation](Bucket: 'bucket', ContentMD5: '000').build()
        hash = AWS.util.crypto.md5(req.httpRequest.body, 'base64')
        expect(req.httpRequest.headers['Content-MD5']).to.equal(hash)

  describe 'willComputeChecksums', ->
    willCompute = (operation, opts) ->
      compute = opts.computeChecksums
      s3 = new AWS.S3(computeChecksums: compute, signatureVersion: 's3')
      req = s3.makeRequest(operation, Bucket: 'example', ContentMD5: opts.hash).build()
      checksum = req.httpRequest.headers['Content-MD5']
      if opts.hash != undefined
        if opts.hash == null
          expect(checksum).not.to.exist
        else
          expect(checksum).to.equal(opts.hash)
      else
        realChecksum = AWS.util.crypto.md5(req.httpRequest.body, 'base64')
        expect(checksum).to.equal(realChecksum)

    it 'computes checksums if the operation requires it', ->
      willCompute 'deleteObjects', computeChecksums: true
      willCompute 'putBucketCors', computeChecksums: true
      willCompute 'putBucketLifecycle', computeChecksums: true
      willCompute 'putBucketLifecycleConfiguration', computeChecksums: true
      willCompute 'putBucketTagging', computeChecksums: true
      willCompute 'putBucketReplication', computeChecksums: true

    it 'computes checksums if computeChecksums is off and operation requires it', ->
      willCompute 'deleteObjects', computeChecksums: false
      willCompute 'putBucketCors', computeChecksums: false
      willCompute 'putBucketLifecycle', computeChecksums: false
      willCompute 'putBucketLifecycleConfiguration', computeChecksums: false
      willCompute 'putBucketTagging', computeChecksums: false
      willCompute 'putBucketReplication', computeChecksums: false

    it 'does not compute checksums if computeChecksums is off', ->
      willCompute 'putObject', computeChecksums: false, hash: null

    it 'does not compute checksums if computeChecksums is on and ContentMD5 is provided', ->
      willCompute 'putBucketAcl', computeChecksums: true, hash: '000'

    it 'computes checksums if computeChecksums is on and ContentMD5 is not provided',->
      willCompute 'putBucketAcl', computeChecksums: true

    if AWS.util.isNode()
      it 'does not compute checksums for Stream objects', ->
        s3 = new AWS.S3(computeChecksums: true)
        req = s3.putObject(Bucket: 'example', Key: 'foo', Body: new Stream.Stream)
        expect(req.build(->).httpRequest.headers['Content-MD5']).to.equal(undefined)

      it 'throws an error in SigV4, if a non-file stream is provided when body signing enabled', (done) ->
        s3 = new AWS.S3({signatureVersion: 'v4', s3DisableBodySigning: false})
        req = s3.putObject(Bucket: 'example', Key: 'key', Body: new Stream.Stream)
        req.send (err) ->
          expect(err.message).to.contain('stream objects are not supported')
          done()

      it 'does not throw an error in SigV4, if a non-file stream is provided when body signing disabled with ContentLength', (done) ->
        s3 = new AWS.S3({signatureVersion: 'v4', s3DisableBodySigning: true})
        helpers.mockResponse data: ETag: 'etag'
        req = s3.putObject(Bucket: 'example', Key: 'key', Body: new Stream.Stream, ContentLength: 10)
        req.send (err) ->
          expect(err).not.to.exist
          done()          

      it 'opens separate stream if a file object is provided (signed payload)', (done) ->
        hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        helpers.mockResponse data: ETag: 'etag'

        fs = require('fs')
        mock = helpers.spyOn(fs, 'createReadStream').andCallFake ->
          tr = new Stream.Transform
          tr._transform = (d,e,c) -> c(null,d)
          tr.length = 0
          tr.path = 'path/to/file'
          tr.push(new Buffer(''))
          tr.end()
          tr

        s3 = new AWS.S3({signatureVersion: 'v4', s3DisableBodySigning: false})
        stream = fs.createReadStream('path/to/file')
        req = s3.putObject(Bucket: 'example', Key: 'key', Body: stream)
        req.send (err) ->
          expect(mock.calls[0].arguments).to.eql(['path/to/file'])
          expect(mock.calls[1].arguments).to.eql(['path/to/file', {}])
          expect(err).not.to.exist
          expect(req.httpRequest.headers['X-Amz-Content-Sha256']).to.equal(hash)
          done()

      it 'opens separate stream with range if a file object is provided', (done) ->
        hash = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08'
        helpers.mockResponse data: ETag: 'etag'

        fs = require('fs')
        mock = helpers.spyOn(fs, 'createReadStream').andCallFake (path, settings) ->
          tr = new Stream.Readable
          tr.length = 0
          tr.path = 'path/to/file'
          tr.start = settings.start
          tr.end = settings.end
          didRead = false
          tr._read = (n) ->
            if (didRead)
              tr.push(null)
            else
              didRead = true
              tr.push(new Buffer('test'))
          tr

        s3 = new AWS.S3(signatureVersion: 'v4', s3DisableBodySigning: false)
        stream = fs.createReadStream('path/to/file', {start:0, end:5})
        req = s3.putObject(Bucket: 'example', Key: 'key', Body: stream)
        req.send (err) ->
          expect(mock.calls[0].arguments).to.eql(['path/to/file', {start:0, end:5}])
          expect(mock.calls[1].arguments).to.eql(['path/to/file', {start:0, end:5}])
          expect(err).not.to.exist
          expect(req.httpRequest.headers['X-Amz-Content-Sha256']).to.equal(hash)
          done()

  describe 'getSignedUrl', ->
    date = null
    beforeEach (done) ->
      date = AWS.util.date.getDate
      AWS.util.date.getDate = -> new Date(0)
      done()

    afterEach (done) ->
      AWS.util.date.getDate = date
      done()

    it 'gets a signed URL for getObject', ->
      url = s3.getSignedUrl('getObject', Bucket: 'bucket', Key: 'key')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/key?AWSAccessKeyId=akid&Expires=900&Signature=4mlYnRmz%2BBFEPrgYz5tXcl9Wc4w%3D&x-amz-security-token=session')

    it 'gets a signed URL with Expires time', ->
      url = s3.getSignedUrl('getObject', Bucket: 'bucket', Key: 'key', Expires: 60)
      expect(url).to.equal('https://bucket.s3.amazonaws.com/key?AWSAccessKeyId=akid&Expires=60&Signature=kH2pMK%2Fgm7cCZKVG8GHVTRGXKzY%3D&x-amz-security-token=session')

    it 'gets a signed URL with expiration and bound bucket parameters', ->
      s3 = new AWS.S3(paramValidation: true, region: undefined, params: Bucket: 'bucket')
      url = s3.getSignedUrl('getObject', Key: 'key', Expires: 60)
      expect(url).to.equal('https://bucket.s3.amazonaws.com/key?AWSAccessKeyId=akid&Expires=60&Signature=kH2pMK%2Fgm7cCZKVG8GHVTRGXKzY%3D&x-amz-security-token=session')

    it 'generates the right URL with a custom endpoint', ->
      s3 = new AWS.S3(endpoint: 'https://foo.bar.baz:555/prefix', params: Bucket: 'bucket')
      url = s3.getSignedUrl('getObject', Key: 'key', Expires: 60)
      expect(url).to.equal('https://bucket.foo.bar.baz:555/prefix/key?AWSAccessKeyId=akid&Expires=60&Signature=zA6k0cQqDkTZgLamfoYLOd%2Bqfg8%3D&x-amz-security-token=session')

    it 'gets a signed URL with callback', (done) ->
      s3.getSignedUrl 'getObject', Bucket: 'bucket', Key: 'key', (err, url) ->
        expect(url).to.equal('https://bucket.s3.amazonaws.com/key?AWSAccessKeyId=akid&Expires=900&Signature=4mlYnRmz%2BBFEPrgYz5tXcl9Wc4w%3D&x-amz-security-token=session')
        done()

    it 'gets a signed URL for putObject with no body', ->
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/key?AWSAccessKeyId=akid&Expires=900&Signature=J%2BnWZ0lPUfLV0kio8ONhJmAttGc%3D&x-amz-security-token=session')

    it 'gets a signed URL for putObject with Metadata', ->
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key', Metadata: {someKey: 'someValue'})
      expect(url).to.equal('https://bucket.s3.amazonaws.com/key?AWSAccessKeyId=akid&Expires=900&Signature=5Lcbv0WLGWseQhtmNQ8WwIpX6Kw%3D&x-amz-meta-somekey=someValue&x-amz-security-token=session')

    it 'gets a signed URL for putObject with Metadata using Sigv4', ->
      s3 = new AWS.S3
        signatureVersion: 'v4'
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key', Metadata: {someKey: 'someValue'})
      expect(url).to.equal('https://bucket.s3.mock-region.amazonaws.com/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=akid%2F19700101%2Fmock-region%2Fs3%2Faws4_request&X-Amz-Date=19700101T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=session&X-Amz-Signature=0a1ef336042a7a03b8a2e130ac36097cb1fbab54f8ed5105977a863a5139e679&X-Amz-SignedHeaders=host%3Bx-amz-meta-somekey&x-amz-meta-somekey=someValue')

    it 'gets a signed URL for putObject with special characters', ->
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: '!@#$%^&*();\':"{}[],./?`~')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/%21%40%23%24%25%5E%26%2A%28%29%3B%27%3A%22%7B%7D%5B%5D%2C./%3F%60~?AWSAccessKeyId=akid&Expires=900&Signature=9nEltJACZKsriZqU2cmRel6g8LQ%3D&x-amz-security-token=session')

    it 'gets a signed URL for putObject with a body (and checksum)', ->
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key', Body: 'body')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/key?AWSAccessKeyId=akid&Content-MD5=hBotaJrYa9FhFEdFPCLG%2FA%3D%3D&Expires=900&Signature=4ycA2tpHKxfFnNCdqnK1d5BG8gc%3D&x-amz-security-token=session')

    it 'gets a signed URL for putObject with a sse-c algorithm', ->
      s3 = new AWS.S3
        signatureVersion: 'v4'
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key', SSECustomerAlgorithm: 'AES256')
      expect(url).to.equal('https://bucket.s3.mock-region.amazonaws.com/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=akid%2F19700101%2Fmock-region%2Fs3%2Faws4_request&X-Amz-Date=19700101T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=session&X-Amz-Signature=60b08f91f820fa1c698ac477fec7b5e3cec7b682e09e769e1a55a4d5a3b99077&X-Amz-SignedHeaders=host%3Bx-amz-server-side-encryption-customer-algorithm&x-amz-server-side-encryption-customer-algorithm=AES256');

    it 'gets a signed URL for putObject with a sse-c key', ->
      s3 = new AWS.S3
        signatureVersion: 'v4'
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key', SSECustomerAlgorithm: 'AES256', SSECustomerKey: 'c2FtcGxlIGtleXNhbXBsZSBrZXlzYW1wbGUga2V5c2E=')
      expect(url).to.equal('https://bucket.s3.mock-region.amazonaws.com/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=akid%2F19700101%2Fmock-region%2Fs3%2Faws4_request&X-Amz-Date=19700101T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=session&X-Amz-Signature=e4f57734798fdadc0b2b43ca5a5e1f28824786c3ac74c30d7abb77d6ef59b0da&X-Amz-SignedHeaders=host%3Bx-amz-server-side-encryption-customer-algorithm%3Bx-amz-server-side-encryption-customer-key%3Bx-amz-server-side-encryption-customer-key-md5&x-amz-server-side-encryption-customer-algorithm=AES256&x-amz-server-side-encryption-customer-key=YzJGdGNHeGxJR3RsZVhOaGJYQnNaU0JyWlhsellXMXdiR1VnYTJWNWMyRT0%3D&x-amz-server-side-encryption-customer-key-MD5=VzaXhwL7H9upBc%2Fb9UqH8g%3D%3D');

    it 'gets a signed URL for putObject with CacheControl', ->
      s3 = new AWS.S3
        signatureVersion: 'v4'
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key', CacheControl: 'max-age=10000')
      expect(url).to.equal('https://bucket.s3.mock-region.amazonaws.com/key?Cache-Control=max-age%3D10000&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=akid%2F19700101%2Fmock-region%2Fs3%2Faws4_request&X-Amz-Date=19700101T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=session&X-Amz-Signature=39ad1f8dc3aa377c2b184a0be7657dfb606628c74796c1a48394ef134ff6233a&X-Amz-SignedHeaders=cache-control%3Bhost')

    it 'gets a signed URL and appends to existing query parameters', ->
      url = s3.getSignedUrl('listObjects', Bucket: 'bucket', Prefix: 'prefix')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/?AWSAccessKeyId=akid&Expires=900&Signature=8W3pwZPfgucCyPNg1MsoYq8h5zw%3D&prefix=prefix&x-amz-security-token=session')

    it 'gets a signed URL for getObject using SigV4', ->
      s3 = new AWS.S3(signatureVersion: 'v4', region: undefined)
      url = s3.getSignedUrl('getObject', Bucket: 'bucket', Key: 'object')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/object?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=akid%2F19700101%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=19700101T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=session&X-Amz-Signature=05ae40d2d22c93549a1de0686232ff56baf556876ec497d0d8349431f98b8dfe&X-Amz-SignedHeaders=host')

    it 'gets a signed URL for putObject using SigV4', ->
      s3 = new AWS.S3(signatureVersion: 'v4', region: undefined)
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'object')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/object?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=akid%2F19700101%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=19700101T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=session&X-Amz-Signature=1b6f75301a2e480bcfbb53d47d8940c28c8657ea70f23c24846a5595a53b1dfe&X-Amz-SignedHeaders=host')

    it 'gets a signed URL for putObject using SigV4 with body', ->
      s3 = new AWS.S3(signatureVersion: 'v4', region: undefined)
      url = s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'object', Body: 'foo')
      expect(url).to.equal('https://bucket.s3.amazonaws.com/object?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae&X-Amz-Credential=akid%2F19700101%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=19700101T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=session&X-Amz-Signature=600a64aff20c4ea6c28d11fd0639fb33a0107d072f4c2dd1ea38a16d057513f3&X-Amz-SignedHeaders=host%3Bx-amz-content-sha256')

    it 'errors when expiry time is greater than a week out on SigV4', (done) ->
      err = null; data = null
      s3 = new AWS.S3(signatureVersion: 'v4', region: undefined)
      params = Bucket: 'bucket', Key: 'object', Expires: 60 * 60 * 24 * 7 + 120
      error = 'Presigning does not support expiry time greater than a week with SigV4 signing.'
      s3.getSignedUrl 'getObject', params, (err, data) ->
        expect(err).not.to.equal(null)
        expect(err.message).to.equal(error)
        #expect(-> s3.getSignedUrl('getObject', params)).to.throw(error) # sync mode
        done()

    it 'errors if ContentLength is passed as parameter', ->
      expect(-> s3.getSignedUrl('putObject', Bucket: 'bucket', Key: 'key', ContentLength: 5)).to.
        throw(/ContentLength is not supported in pre-signed URLs/)
