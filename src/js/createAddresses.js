let fs = require('fs');

const jsonFile = process.argv[2];
let addresses = require(jsonFile);

const solFile = './src/contracts/addresses.sol';

let code = `
pragma solidity >=0.5.15 <0.6.0;

contract TinlakeAddresses {

`;

if (fs.existsSync(solFile)) {
    fs.unlinkSync(solFile);
}

for (const item in addresses) {
    code += "address public constant " + item  +" = "  + addresses[item] + "; \n";
}
code += "\n}";

console.log(code);

fs.appendFile(solFile, code, function (err) {
    if (err) {
        console.log(err);
    }
});




