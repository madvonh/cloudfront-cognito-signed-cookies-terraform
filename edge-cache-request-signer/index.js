const AWS = require("aws-sdk");
const jwt = require("jsonwebtoken");
const jwkToPem = require("jwk-to-pem");
const https = require("https");

const ssm = new AWS.SSM({ region: "us-east-1" });

const cache = {};

const headersToAllow =
  "accept,content-type,access-control-allow-credentials,access-control-allow-headers,access-control-allow-origin,authorization,origin,access-control-max-age";

const loadParameter = async (key, WithDecryption = false) => {
  const { Parameter } = await ssm
    .getParameter({ Name: key, WithDecryption: WithDecryption })
    .promise();
  return Parameter.Value;
};

const getCognitoPublicKeys = (cognitoHost, issuer) => {
  return new Promise((resolve, reject) => {
    const keysPath = issuer + "/.well-known/jwks.json";

    https
      .get({ host: cognitoHost, path: keysPath }, function (res) {
        var data = "";
        res.on("data", function (chunk) {
          data += chunk;
        });
        res.on("end", function () {
          if (res.statusCode === 200) {
            var res_body = JSON.parse(data);
            return resolve(res_body["keys"]);
          } else {
            console.log("Status:", res.statusCode);
          }
        });
      })
      .on("error", function (err) {
        console.log("Error:", err);
        return reject(
          new Error("Error while getting JWKs. " + JSON.stringify(err, null, 2))
        );
      });
  });
};

const verify = (jwtToken, pem, issuer) => {
  return new Promise((resolve, reject) => {
    jwt.verify(jwtToken, pem, { issuer: issuer }, (err, payload) => {
      if (err) {
        switch (err.name) {
          case "TokenExpiredError":
            reject(new Error("JWT Token Expired."));
            break;
          case "JsonWebTokenError":
            reject(new Error("Invalid JWT Token."));
            break;
          default:
            reject(
              new Error(
                "Token verification failure. " + JSON.stringify(err, null, 2)
              )
            );
        }
      } else {
        resolve(payload);
      }
    });
  });
};

const getPolicyString = (cloudfrontDomain, expirationTimeInMinuits) => {
  return JSON.stringify({
    Statement: [
      {
        Resource: "https://" + cloudfrontDomain + "/*",
        Condition: {
          DateLessThan: {
            "AWS:EpochTime": getExpiryTime(expirationTimeInMinuits),
          },
        },
      },
    ],
  });
};

const getSignedCookie = (
  keypairId,
  privateKey,
  cloudfrontDomain,
  expirationTimeInMinuits
) => {
  const cloudFront = new AWS.CloudFront.Signer(keypairId, privateKey);
  const options = {
    policy: getPolicyString(cloudfrontDomain, expirationTimeInMinuits),
  };

  return cloudFront.getSignedCookie(options);
};

const getExpirationTime = (expirationTimeInMinuits) => {
  let date = new Date();
  date.setMinutes(date.getMinutes() + expirationTimeInMinuits);
  return date;
};

const getExpiryTime = (expirationTimeInMinuits) => {
  return Math.floor(
    getExpirationTime(expirationTimeInMinuits).getTime() / 1000
  );
};

const verifyToken = async (
  decodedJwt,
  issuer,
  clientId,
  cognitoHost,
  jwtToken
) => {
  // Fail if the token is not jwt
  if (!decodedJwt) {
    throw new Error("Not a valid JWT Token");
  }

  // Fail if token issure is invalid
  if (decodedJwt.payload.iss !== issuer) {
    throw new Error("Invalid issuer: " + decodedJwt.payload.iss + " " + issuer);
  }

  // Reject the jwt if it's not an id token
  if (!(decodedJwt.payload.token_use === "id")) {
    throw new Error("Invalid token_use: " + decodedJwt.payload.token_use);
  }

  // Fail if token audience is invalid
  if (decodedJwt.payload.aud !== clientId) {
    throw new Error("Invalid aud: " + decodedJwt.payload.aud);
  }

  const keys = await getCognitoPublicKeys(cognitoHost, issuer);

  // Get the kid from the token and compair with key
  const kid = decodedJwt.header.kid;
  if (!kid || keys[0].kid !== kid) {
    throw new Error("Invalid kid: " + decodedJwt.header.kid);
  }

  const pem = jwkToPem(keys[0]);

  const result = await verify(jwtToken, pem, issuer);
  // if we got here without errors the token is valid
  // console.log(JSON.stringify(result));
};

const preflightCall = (origin) => {
  return {
    status: "204",
    statusDescription: "No Content",
    headers: sharedHeaders(origin),
  };
};

const getCookieRespons = (
  signedCookie,
  cloudfrontDomain,
  clientUrl,
  expirationTimeInMinuits,
  remove = false
) => {
  const expirationTime = remove
    ? "Thu, 01 Jan 1970 00:00:01 GMT"
    : getExpirationTime(expirationTimeInMinuits).toString();
  const cloudFrontPolicy = remove ? "" : signedCookie["CloudFront-Policy"];
  const cloudFrontKeyPairId = remove
    ? ""
    : signedCookie["CloudFront-Key-Pair-Id"];
  const cloudFrontSignature = remove
    ? ""
    : signedCookie["CloudFront-Signature"];

  return {
    status: "200",
    statusDescription: "OK",
    headers: Object.assign({}, sharedHeaders(clientUrl), {
      "set-cookie": [
        {
          key: "Set-Cookie",
          value:
            "CloudFront-Policy=" +
            cloudFrontPolicy +
            "; Domain=." +
            cloudfrontDomain +
            "; Path=/; Expires=" +
            expirationTime +
            "; HttpOnly; Secure; SameSite=None",
        },
        {
          key: "Set-Cookie",
          value:
            "CloudFront-Key-Pair-Id=" +
            cloudFrontKeyPairId +
            "; Domain=." +
            cloudfrontDomain +
            "; Path=/; Expires=" +
            expirationTime +
            "; HttpOnly; Secure; SameSite=None",
        },
        {
          key: "Set-Cookie",
          value:
            "CloudFront-Signature=" +
            cloudFrontSignature +
            "; Domain=." +
            cloudfrontDomain +
            "; Path=/; Expires=" +
            expirationTime +
            "; HttpOnly; Secure; SameSite=None",
        },
      ],
    }),
  };
};

const errorRespons = (clientUrl, status, statusDescription, errorMessage) => {
  return {
    body: errorMessage,
    bodyEncoding: "text",
    status: status,
    statusDescription: statusDescription,
    headers: sharedHeaders(clientUrl),
  };
};

const sharedHeaders = (clientUrl) => {
  return {
    "access-control-allow-origin": [
      {
        key: "Access-Control-Allow-Origin",
        value: clientUrl,
      },
    ],
    "access-control-allow-methods": [
      {
        key: "Access-Control-Allow-Methods",
        value: "GET,HEAD,OPTIONS",
      },
    ],
    "access-control-allow-headers": [
      {
        key: "Access-Control-Allow-Headers",
        value: headersToAllow,
      },
    ],
    "cache-control": [
      {
        key: "Cache-Control",
        value: "no-cache,no-store,must-revalidate",
      },
    ],
    "access-control-allow-credentials": [
      {
        key: "Access-Control-Allow-Credentials",
        value: "true",
      },
    ],
  };
};

const setDomainCacheValue = async () => {
  if (cache.cloudfrontDomain == null) {
    cache.cloudfrontDomain = await loadParameter(
      `${ssm_prefix}-cloudfront-domain`
    );
  }
};

const setAuthCacheValues = async () => {
  if (cache.privateKeyRef == null) {
    cache.privateKeyRef = await loadParameter(`${ssm_prefix}-signing-key-ref`);
  }

  if (cache.cloudfrontKeypair == null) {
    cache.cloudfrontKeypair = await loadParameter(
      `${ssm_prefix}-cloudfront-keypair-id`
    );
  }

  if (cache.region == null) {
    cache.region = await loadParameter(`${ssm_prefix}-region`);
  }

  if (cache.userPoolId == null) {
    cache.userPoolId = await loadParameter(`${ssm_prefix}-user-pool-id`);
  }

  if (cache.clientId == null) {
    cache.clientId = await loadParameter(`${ssm_prefix}-client-id`);
  }
  if (cache.expirationTimeInMinuits == null) {
    const result = await loadParameter(
      `${ssm_prefix}-expiration-time-in-minuits`
    );
    cache.expirationTimeInMinuits = parseInt(result, 10);
  }

  if (cache.privateKey == null) {
    cache.privateKey = await loadParameter(cache.privateKeyRef, true);
  }
};

exports.handler = async (event, context, callback) => {
  const clientUrl = event.Records[0].cf.request.headers.origin[0].value;
  const request = event.Records[0].cf.request;

  if (request.method === "OPTIONS") {
    console.log("preflight call");
    callback(null, preflightCall(clientUrl));
    return;
  }

  try {
    await setDomainCacheValue();
    const { cloudfrontDomain } = cache;

    if (request.uri.endsWith("/remove")) {
      const expireCookie = getCookieRespons(
        null,
        cloudfrontDomain,
        clientUrl,
        null,
        true
      );
      callback(null, expireCookie);
      return;
    }

    if (
      !(
        "authorization" in request.headers &&
        request.headers.authorization.length === 1
      )
    ) {
      const err = errorRespons(
        clientUrl,
        "403",
        "Forbidden",
        "Missing authorization header"
      );
      console.log(JSON.stringify(err));
      callback(null, err);
      return;
    }

    const auth = request.headers.authorization[0].value.split(" ");

    if (auth.length !== 2 || auth[0] !== "Bearer" || auth[1].length < 1) {
      console.log("Incorrect authorization header");
      const err = errorRespons(
        clientUrl,
        "403",
        "Forbidden",
        "Incorrect authorization header"
      );
      callback(null, err);
      return;
    }
    const jwtToken = auth[1];
    const decodedJwt = jwt.decode(jwtToken, { complete: true });

    await setAuthCacheValues();
    const {
      cloudfrontKeypair,
      privateKey,
      region,
      userPoolId,
      clientId,
      expirationTimeInMinuits,
    } = cache;
    const cognitoHost = "cognito-idp." + region + ".amazonaws.com";
    const issuer = "https://" + cognitoHost + "/" + userPoolId;

    try {
      await verifyToken(decodedJwt, issuer, clientId, cognitoHost, jwtToken);
    } catch (error) {
      console.log(error);
      const err = errorRespons(
        clientUrl,
        "401",
        "Unauthorized",
        error.message || "Undefined error"
      );
      callback(null, err);
      return;
    }
    console.log("Verified token");

    const signedCookie = getSignedCookie(
      cloudfrontKeypair,
      privateKey,
      cloudfrontDomain,
      expirationTimeInMinuits
    );

    console.log("Got signed cookie");
    return getCookieRespons(
      signedCookie,
      cloudfrontDomain,
      clientUrl,
      expirationTimeInMinuits,
      false
    );
  } catch (error) {
    console.log(error);
    const err = errorRespons(
      clientUrl,
      "400",
      "Bad Request",
      error.message || "Undefined error"
    );
    callback(null, err);
    return;
  }
};

// optional claims examples
// if we where to validate the claims to see if the user belongs to a certain group
/*
const params = {
  region: region, 
  userPoolId: 'us-west-2_H8xaPj7fC', 
  debug: true // optional parameter to show console logs
}

const claims = {
  aud: '5nckn0n3v1a3efplt27p5cnpkg', // clientId
  email_verified: true,
  auth_time: time => time <= 1524588564,
  'cognito:groups': groups => groups.includes('Admins')
}

const verifier = new Verifier(params, claims);
*/
