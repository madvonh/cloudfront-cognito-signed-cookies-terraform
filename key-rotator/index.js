const AWS = require("aws-sdk");
const { generateKeyPair } = require("crypto");

const region = process.env.REGION;
const secretName = process.env.SECRET_NAME;
const keyGroupId = process.env.KEY_GROUP_ID;
const prefix = process.env.PREFIX;
const dummyKeyName = prefix + "-DUMMY_KEY";
const key1Name = prefix + "-KEY_1";
const key2Name = prefix + "-KEY_2";
const ssmParmeterName = process.env.SSM_PARAM;

const cloudFrontClient = new AWS.CloudFront({ region });
const ssm = new AWS.SSM({ region: "us-east-1" });

async function createAndUploadKeyPair() {
  const { privateKey, publicKey } = await getRSAKeyPair();
  const secretsManagerClient = new AWS.SecretsManager({ region });

  const keys = await listPublicKeys();
  const key1 = keys.find((key) => key.Name === key1Name);
  const key2 = keys.find((key) => key.Name === key2Name);
  const dummyKey = keys.find((key) => key.Name === dummyKeyName);
  let keyToCreate = key1Name;
  let keyIdToKeep;
  if (key1 && key2) {
    const key1WithEtag = await getPublicKey(key1.Id);
    const key2WithEtag = await getPublicKey(key2.Id);
    let keyToDelete = key1WithEtag;
    let itemsInKeyGroup = [key2.Id];

    // Pick the oldest one to remove
    if (
      key1WithEtag.PublicKey.CreatedTime > key2WithEtag.PublicKey.CreatedTime
    ) {
      keyToDelete = key2WithEtag;
      keyToCreate = key2Name;
      keyIdToKeep = key1WithEtag.PublicKey.Id;
      itemsInKeyGroup = [key1.Id];
    } else {
      keyIdToKeep = key2WithEtag.PublicKey.Id;
    }

    // Removes the key from keygroup before removal
    await updateKeyGroup(itemsInKeyGroup);

    const params = {
      Id: keyToDelete.PublicKey.Id,
      IfMatch: keyToDelete.ETag,
    };

    await cloudFrontClient.deletePublicKey(params).promise();
    console.log(
      `Old public key "${keyToDelete.PublicKey.PublicKeyConfig.Name}" "${keyToDelete.PublicKey.Id}" deleted.`
    );
  } else if (key1) {
    keyToCreate = key2Name;
  }

  const publicKeyConfig = {
    PublicKeyConfig: {
      CallerReference: Date.now().toString(),
      Name: keyToCreate,
      EncodedKey: publicKey,
    },
  };

  const newKey = await cloudFrontClient
    .createPublicKey(publicKeyConfig)
    .promise();
  console.log(
    `New public key "${keyToCreate}" "${newKey.PublicKey.Id}" created.`
  );

  const items = keyIdToKeep
    ? [keyIdToKeep, newKey.PublicKey.Id]
    : [newKey.PublicKey.Id];

  // Final update to keygroup with newly created key
  await updateKeyGroup(items);

  await secretsManagerClient
    .updateSecret({
      SecretId: secretName,
      SecretString: privateKey,
    })
    .promise();

  await updateParameter(ssmParmeterName, newKey.PublicKey.Id);

  // If we have updated through Terraform there will be a dummy key.
  // Its not used, so we remove it.
  if (dummyKey) {
    const dummyKeyWithEtag = await getPublicKey(dummyKey.Id);
    const params = {
      Id: dummyKey.Id,
      IfMatch: dummyKeyWithEtag.ETag,
    };

    await cloudFrontClient.deletePublicKey(params).promise();
    console.log(
      `Public key dummy "${dummyKey.Name}" "${dummyKey.Id}" deleted.`
    );
  }
}

async function updateParameter(name, privateKey) {
  var params = {
    Name: name,
    Value: privateKey,
    Type: "String",
    Overwrite: true,
    Tier: "Standard",
  };

  const res = await ssm.putParameter(params).promise();
}

async function updateKeyGroup(items) {
  const keygroup = await cloudFrontClient
    .getKeyGroup({ Id: keyGroupId })
    .promise();

  const trustedKeyConfig = {
    KeyGroupConfig: {
      Items: items,
      Name: keygroup.KeyGroup.KeyGroupConfig.Name,
    },
    Id: keygroup.KeyGroup.Id,
    IfMatch: keygroup.ETag,
  };
  await cloudFrontClient.updateKeyGroup(trustedKeyConfig).promise();

  console.log(
    `CloudFront trusted key group "${keyGroupId}" is updated with the public key items "${JSON.stringify(
      items
    )}".`
  );
}

async function listPublicKeys() {
  return new Promise((resolve, reject) => {
    cloudFrontClient.listPublicKeys(null, function (err, data) {
      if (err) {
        console.log(err, err.stack);
        reject(err);
      } else {
        resolve(data.PublicKeyList.Items);
      }
    });
  });
}

async function getPublicKey(id) {
  return new Promise((resolve, reject) => {
    cloudFrontClient.getPublicKey({ Id: id }, function (err, data) {
      if (err) {
        console.log(err, err.stack);
        reject(err);
      } else {
        resolve(data);
      }
    });
  });
}

async function getRSAKeyPair() {
  return new Promise((resolve, reject) => {
    generateKeyPair(
      "rsa",
      {
        modulusLength: 2048,
        publicKeyEncoding: {
          type: "spki",
          format: "pem",
        },
        privateKeyEncoding: {
          type: "pkcs8",
          format: "pem",
        },
      },
      (err, publicKey, privateKey) => {
        if (!err) {
          resolve({ publicKey, privateKey });
        } else {
          console.log("Err is: ", err);
          reject(err);
        }
      }
    );
  });
}

exports.handler = async (event, context, callback) => {
  try {
    await createAndUploadKeyPair();
  } catch (err) {
    console.log(err);
    callback(err);
  }
};
