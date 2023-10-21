// index.js
// https://github.com/googleapis/google-cloud-node/blob/main/packages/google-cloud-secretmanager/samples 
const express = require('express');
const app = express();
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager').v1;
const secretmanagerClient = new SecretManagerServiceClient();

async function getSecretVersion(secret) {
  const [version] = await secretmanagerClient.accessSecretVersion(secret);
  payload = version.payload.data.toString();
  console.log({version, payload});
  return payload;
}

// set secret value on instantiation
const projectId   = process.env.PROJECT_ID || 'mike-test-cmdb-gke';
const secretId    = process.env.SECRET_ID || 'foo';
const versionId   = process.env.SECRET_VERSION_ID || 'latest';
const port        = process.env.PORT || 3000;
const secret = {
  name: `projects/${projectId}/secrets/${secretId}/versions/${versionId}`,
}

getSecretVersion(secret).then((foo) => {
  app.get('/', (req, res) => {
    res.send(`Hello World! G\'day ${foo}!`)
  })
  
  app.listen(port, () => console.log(`Server is up and running on port ${port} with secret foo=${foo}`));
}).catch((err) => {
  console.log(err);
});
