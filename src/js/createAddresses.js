let fs = require('fs');

const jsonFile = process.argv[2];
let addresses = require(jsonFile);

const solFile = './src/contracts/addresses.sol';

let code = `
// The following addresses are from a json file called: ` + jsonFile.replace(/^.*[\\\/]/, '') +
    `

pragma solidity >=0.7.0;

// Autogenerated Solidity Tinlake Address Contract 
contract TinlakeAddresses {

`;

if (fs.existsSync(solFile)) {
    fs.unlinkSync(solFile);
}

for (const item in addresses) {
    code += "address public " + item  +" = "  + addresses[item] + "; \n";
}
code += "\n}";

console.log(code);

fs.appendFile(solFile, code, function (err) {
    if (err) {
        console.log(err);
    }
});




