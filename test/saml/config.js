/**
 * SAML IdP assertion attribute config for mock Feilian.
 * These attributes simulate what Feilian would send in a real SAML assertion.
 */
module.exports = {
  user: {
    userName: "testuser@example.com",
    email: "testuser@example.com",
    firstName: "Test",
    lastName: "User",
    displayName: "Test User",
    department: "Engineering",
  },
  metadata: [
    {
      id: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
      optional: false,
      displayName: "E-Mail Address",
      description: "The e-mail address of the user",
      multiValue: false,
    },
    {
      id: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
      optional: false,
      displayName: "Name",
      description: "The full name of the user",
      multiValue: false,
    },
    {
      id: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/department",
      optional: true,
      displayName: "Department",
      description: "The department of the user",
      multiValue: false,
    },
  ],
};
