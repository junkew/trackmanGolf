# trackmanGolf
Retrieve my statistics from Trackman History with GraphQL


## Steps for retrieving with powershell

1. Logon with your browser to https://portal.trackmangolf.com/player/activities
2. Start the developer tools
3. Start your powershell (ISE 5.1 + Windows 11 tested) session
4. Open the PS1 script from the repo
5. Copy/paste your bearer token to the environment of your powershell session
   $env:bearertoken="Bearer eyJ ....."
6. Run your powershell script
