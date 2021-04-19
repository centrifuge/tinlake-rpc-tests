interface AuthLike {
    function rely(address) external;
    function deny(address) external;
    function wards(address) external returns(uint);
}

interface RootLike {
    function relyContract(address contractAddr, address addr) external;
}
