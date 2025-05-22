// SharePoint upload using GitHub Actions JavaScript API
const fs = require('fs');
const path = require('path');
const https = require('https');
const querystring = require('querystring');

// Configuration from environment variables
const tenantId = process.env.TENANT_ID;
const clientId = process.env.CLIENT_ID;
const clientSecret = process.env.CLIENT_SECRET;
const siteId = process.env.SITE_ID;
const driveIdEnv = process.env.DRIVE_ID;
const folderPath = process.env.FOLDER_PATH || 'Diagrams';
const fileName = process.env.FILE_NAME || 'Diagrams_Changelog.csv';
const filePath = process.env.FILE_PATH || 'png_files/CHANGELOG.csv';

// HTTP request wrapper with promises
const httpRequest = (options, postData) => {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let responseBody = '';
      res.setEncoding('utf8');
      
      res.on('data', (chunk) => {
        responseBody += chunk;
      });
      
      res.on('end', () => {
        console.log(`HTTP Status: ${res.statusCode}`);
        
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            const data = JSON.parse(responseBody);
            resolve(data);
          } catch (e) {
            // Not JSON, return as is
            resolve(responseBody);
          }
        } else {
          console.error(`API Error (${res.statusCode}): ${responseBody}`);
          reject(new Error(`API Error: ${res.statusCode} - ${responseBody}`));
        }
      });
    });
    
    req.on('error', (e) => {
      console.error(`Request error: ${e.message}`);
      reject(e);
    });
    
    if (postData) {
      req.write(postData);
    }
    
    req.end();
  });
};

// Main execution function
async function uploadToSharePoint() {
  try {
    console.log('Starting SharePoint upload process...');
    
    // Check for required parameters
    if (!tenantId || !clientId || !clientSecret || !siteId) {
      throw new Error('Missing required parameters: TENANT_ID, CLIENT_ID, CLIENT_SECRET, SITE_ID');
    }
    
    // Read file content
    console.log(`Reading file from: ${filePath}`);
    if (!fs.existsSync(filePath)) {
      throw new Error(`File not found: ${filePath}`);
    }
    
    const fileContent = fs.readFileSync(filePath, 'utf8');
    console.log(`File size: ${fileContent.length} bytes`);
    console.log(`First few lines: ${fileContent.split('\n').slice(0, 3).join('\n')}...`);
    
    // Step 1: Get access token
    console.log('Obtaining OAuth token...');
    const tokenData = await getAccessToken(tenantId, clientId, clientSecret);
    console.log(`Access token obtained (${tokenData.access_token.length} chars)`);
    
    // Step 2: Get drive ID if not provided
    let driveId = driveIdEnv;
    if (!driveId || driveId === 'auto') {
      console.log('Auto-detecting drive ID...');
      driveId = await getDriveId(siteId, tokenData.access_token);
    }
    console.log(`Using drive ID: ${driveId}`);
    
    // Step 3: Ensure folder exists
    await ensureFolder(siteId, driveId, tokenData.access_token, folderPath);
    
    // Step 4: Upload file
    console.log(`Uploading file to SharePoint: ${folderPath}/${fileName}`);
    
    // Try different upload paths to find one that works
    let uploadResult = null;
    
    // Try 1: Direct to Shared Documents path (preferred approach)
    try {
      console.log('Trying path format 1: Shared Documents/folderPath');
      const uploadPath = `/v1.0/sites/${siteId}/drives/${driveId}/root:/Shared%20Documents/${folderPath}/${fileName}:/content`;
      uploadResult = await uploadFile(uploadPath, tokenData.access_token, fileContent);
    } catch (error) {
      console.log(`Path format 1 failed: ${error.message}`);
      
      // Try 2: Legacy Documents path
      try {
        console.log('Trying path format 2: Documents/folderPath');
        const uploadPath = `/v1.0/sites/${siteId}/drives/${driveId}/root:/Documents/${folderPath}/${fileName}:/content`;
        uploadResult = await uploadFile(uploadPath, tokenData.access_token, fileContent);
      } catch (error2) {
        console.log(`Path format 2 failed: ${error2.message}`);
        
        // Try 3: Root path direct
        try {
          console.log('Trying path format 3: Root/folderPath');
          const uploadPath = `/v1.0/sites/${siteId}/drives/${driveId}/root:/${folderPath}/${fileName}:/content`;
          uploadResult = await uploadFile(uploadPath, tokenData.access_token, fileContent);
        } catch (error3) {
          throw new Error(`All upload paths failed. Last error: ${error3.message}`);
        }
      }
    }
    
    console.log('✅ File uploaded successfully!');
    if (uploadResult && uploadResult.webUrl) {
      console.log(`File URL: ${uploadResult.webUrl}`);
    }
    
    return uploadResult;
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

// Function to get access token
async function getAccessToken(tenantId, clientId, clientSecret) {
  const tokenBody = querystring.stringify({
    client_id: clientId,
    scope: 'https://graph.microsoft.com/.default',
    client_secret: clientSecret,
    grant_type: 'client_credentials'
  });
  
  const options = {
    hostname: 'login.microsoftonline.com',
    path: `/${tenantId}/oauth2/v2.0/token`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': Buffer.byteLength(tokenBody)
    }
  };
  
  return await httpRequest(options, tokenBody);
}

// Function to get drive ID
async function getDriveId(siteId, accessToken) {
  const options = {
    hostname: 'graph.microsoft.com',
    path: `/v1.0/sites/${siteId}/drives`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  };
  
  const response = await httpRequest(options);
  
  if (!response.value || response.value.length === 0) {
    throw new Error('No drives found in the SharePoint site');
  }
  
  // Find the Documents library (typically the first drive)
  let documentsLibrary = response.value.find(drive => 
    drive.name === 'Documents' || drive.name === 'Shared Documents'
  );
  
  // If no specific library found, use the first one
  if (!documentsLibrary) {
    documentsLibrary = response.value[0];
    console.log(`Could not find Documents library, using: ${documentsLibrary.name}`);
  } else {
    console.log(`Found ${documentsLibrary.name} library`);
  }
  
  return documentsLibrary.id;
}

// Function to ensure folder exists
async function ensureFolder(siteId, driveId, accessToken, folderPath) {
  // First check if folder exists
  const checkOptions = {
    hostname: 'graph.microsoft.com',
    path: `/v1.0/sites/${siteId}/drives/${driveId}/root:/${folderPath}`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  };
  
  try {
    await httpRequest(checkOptions);
    console.log(`✅ Folder ${folderPath} already exists`);
    return true;
  } catch (error) {
    // Folder doesn't exist, create it
    console.log(`Creating folder: ${folderPath}`);
    
    const createOptions = {
      hostname: 'graph.microsoft.com',
      path: `/v1.0/sites/${siteId}/drives/${driveId}/root/children`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      }
    };
    
    const folderData = JSON.stringify({
      name: folderPath,
      folder: {},
      '@microsoft.graph.conflictBehavior': 'replace'
    });
    
    await httpRequest(createOptions, folderData);
    console.log(`✅ Folder ${folderPath} created`);
    return true;
  }
}

// Function to upload file
async function uploadFile(uploadPath, accessToken, fileContent) {
  const options = {
    hostname: 'graph.microsoft.com',
    path: uploadPath,
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'text/csv',
      'Content-Length': Buffer.byteLength(fileContent)
    }
  };
  
  return await httpRequest(options, fileContent);
}

// Execute the upload process
uploadToSharePoint().catch(error => {
  console.error(`Failed to upload to SharePoint: ${error.message}`);
  process.exit(1);
});
