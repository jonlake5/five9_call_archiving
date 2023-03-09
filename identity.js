// Initialize the Amazon Cognito credentials provider
AWS.config.region = 'us-east-1'; // Region
AWS.config.credentials = new AWS.CognitoIdentityCredentials({
    IdentityPoolId: 'us-east-1:de2cb63f-7b67-4d8c-88dc-daaf3efba70d',
});

var params = {
    IdentityPoolId: 'us-east-1:de2cb63f-7b67-4d8c-88dc-daaf3efba70d', /* required */
    Logins: {
      '<IdentityProviderName>': 'STRING_VALUE',
      /* '<IdentityProviderName>': ... */
    }
  };
  cognitoidentity.getId(params, function(err, data) {
    if (err) console.log(err, err.stack); // an error occurred
    else     console.log(data);           // successful response
  });