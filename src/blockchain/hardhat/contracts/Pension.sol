// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <=0.8.14;

//import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 *  @title Pension
 *  This contract is a curated registry for people. The users are identified by their address and can be added or removed through the request-challenge protocol.
 *  In order to challenge a registration request the challenger must provide one of the four reasons.
 *  New registration requests firstly should gain sufficient amount of vouches from other registered users and only after that they can be accepted or challenged.
 *  The users who vouched for submission that lost the challenge with the reason Duplicate or DoesNotExist would be penalized with optional fine or ban period.
 *  NOTE: This contract trusts that the Arbitrator is honest and will not reenter or modify its costs during a call.
 *  The arbitrator must support appeal period.
 */

contract Pension is ERC721 {
    using Counters for Counters.Counter;

    Counters.Counter public pensionIdCounter;

    /* Constants and immutable */
    uint256 constant private femaleExpectancyLife = 365 days * 80;
    uint256 constant private interval = 30 days;
    uint256 constant private majorityAge = 18;
    uint256 constant private maleExpectancyLife = 365 days * 85;
    uint256 constant private mininumDeposit = 25;
    uint256 constant private retirentmentAge = 365 days * 61;
    uint256 constant private quantityQuotes = 365 days +39;


    /* Struct */
    struct MonthlyQuote {
        address owner;
        bytes32 id;
        uint256 pensionId;
        uint256 contributionDate;
        uint256 savingAmount; 
        uint256 solidaryAmount; 
        uint256 totalAmount;
    }

    struct MonthlyRecord {
        uint256 totalAmount;
        MonthlyQuote[] monthlyQuotes;
    }

    struct PensionOwner {
        address owner;
        string biologySex;
        uint256 age;
        uint256 bornAge;
        uint256 expectancyAfterRetirement;
        uint256 pensionCreatedTime;
        uint256 pensionId;
    }

    struct RetairedQuote {
        address owner;
        uint256 monthlyQuote;
        uint256 quantityQuotes;
        uint256 totalPaidQuotes;
        uint256 totalPension;
    }

    struct RetairedRecord {
        uint256 totalAmount;
        RetairedQuote[] retairedQuotes;
    }

    /* Storage */

    MonthlyQuote[]  private monthlyQuotes;
    Pension[] private pensions;
    MonthlyRecord[] private monthlyRecords;
    RetairedQuote[] private retairedQuotes;
    RetairedRecord[] private retairedRecords;

    mapping(address => bool) public addressesThatAlreadyMinted;
    mapping(address => mapping(uint256 => uint256)) public savingsBalance;
    mapping(address => mapping(uint256 => uint256)) public solidaryBalance;
    mapping(uint256 => address) public ownerPensionsBalance;
    mapping(uint256 => MonthlyRecord) public generalBalance;
    mapping(uint256 => PensionOwner[]) public cutoffDateWithdrawPensionBalance;
    mapping(uint256 => RetairedRecord) public retairedBalance;

    uint256 public cutoffDate;
    uint256[] private withdrawPensionList;

    /* Modifiers */

    // -- Docs
    // -- Testing --
    modifier onlyOwner(uint256 _pension) {
       require(msg.sender == ownerPensionsBalance[_pension] && msg.sender == ownerOf(_pension), "You don't own this pension"); 
        _;}

    // -- Docs
    // -- Testing --
    modifier validAmount(uint256 _amount) {
        require(msg.value >= mininumDeposit, "The amount doesn't reach the minimum required");
        require(msg.value == _amount, "You don't have this amount");
        _;
    }

    /* Events */

    /** @dev Emitted when a vouch is added.
      * @param _submissionID The submission that receives the vouch.
      * @param _voucher The address that vouched.
    */



    /** @dev Constructor
     *  
    */
    constructor() ERC721 ("Pension", "PNS") {
        cutoffDate = block.timestamp;
        MonthlyRecord storage monthlyRecord = (monthlyRecords.push());
        generalBalance[cutoffDate] = monthlyRecord;
    }

    // ************************ //
    // *     Mint pension     * //
    // ************************ //
    
    // -- Docs
    // -- Testing --
    function safeMint(string memory _biologySex, uint256 _age,  uint256 _bornAge, uint256 _firstQuote) validAmount(_firstQuote) payable public {
        require(!verifyIfTheContributorAlreadyMint(msg.sender), "Already generated his pension");
        require(_age >= majorityAge, "You must be 18 years or older to generate a pension");
        
        uint256 age = _age * 365 days; 
        uint256 expectancyAfterRetirement = determLifeExpectancyAfterRetirement(_biologySex);
        uint256 mintDate = block.timestamp; 

        uint256 pensionId = pensionIdCounter.current();
        pensionIdCounter.increment();
        _safeMint(msg.sender, pensionId);

        PensionOwner memory newPension = PensionOwner(msg.sender, _biologySex, age, _bornAge, expectancyAfterRetirement,  pensionId, mintDate);       

        uint256 timeRetirentment = retirentmentAge - age; 
        uint256 retirentmentDate = mintDate + timeRetirentment; 
        uint256 retirentmentCutoffDate = ((retirentmentDate - cutoffDate) / 30 days) + 30 days;
        cutoffDateWithdrawPensionBalance[retirentmentCutoffDate].push(newPension);  
        
        depositAmount(pensionId, _firstQuote);
        addressesThatAlreadyMinted[msg.sender] = true;
        ownerPensionsBalance[pensionId] = msg.sender; 
    }


    // ************************ //
    // *       Quoutes        * //
    // ************************ //

    /*
      * @dev depositar DAIs según la cantidad anual pactada en el minteo.
      *  @param _pensionId La pensión.
      *  @param _amount DAI a depositar.
    */
    // -- Testing --

    function depositAmount(uint256 _pensionId, uint256 _amount) payable public onlyOwner(_pensionId) validAmount(_amount) {
        
        uint256 contributionDate = block.timestamp;
        uint256 savingsAmount = _amount * 23 / 100;
        uint256 solidaryAmount = _amount * 73 / 100;
        solidaryBalance[msg.sender][_pensionId] += solidaryAmount;
        savingsBalance[msg.sender][_pensionId] += savingsAmount;
        registerMonthlyQuote(_pensionId, _amount, contributionDate, savingsAmount, solidaryAmount);
    }

    /* @dev Register quote deposit in the general balance
     * @param _pensionId La pensión
     * @param _contribution DAI a depositar
     * @param _contributionDate DAI a depositar
     * @param _savingsAmount DAI a depositar
     * @param _solidaryAmount
    */ 
    // -- Testing --
    function registerMonthlyQuote(uint256 _pensionId, uint256 _totalAmount, uint256 _contributionDate, uint256 _savingsAmount, uint256 _solidaryAmount) private {
        bytes32 id = keccak256(abi.encodePacked(_contributionDate));
        generalBalance[cutoffDate].totalAmount += _totalAmount;
        generalBalance[cutoffDate].monthlyQuotes.push(MonthlyQuote(msg.sender, id, _pensionId, _contributionDate, _savingsAmount, _solidaryAmount,  _totalAmount));
    }

    // function setAnnualAmount(uint256 newAnnualAmount, uint256 pensionId) payable public {
    //     // Rango para cotizar más
    //     // todo
    //     require(pensions[pensionId] == ownerOf(pensionId), "You don't own this pension"); // modificar
    //     uint currentTime = block.timestamp;
    //     uint beforeTimetoUpdateAnnualAmount = timeToUpdateAnnualAmount - 2 weeks;
    //     uint afterTimeToUpdateAnnualAmount = timeToUpdateAnnualAmount + 2 weeks;
    //     if(currentTime >= beforeTimetoUpdateAnnualAmount && currentTime <= afterTimeToUpdateAnnualAmount) {
    //         require(newAnnualAmount >= mininumDeposit, "The amount doesn't reach the minimum required");
    //         require(msg.value >= newAnnualAmount, "The amount doesn't reach the new minimum required");
    //         annualAmount = newAnnualAmount;
    //         timeToUpdateAnnualAmount = currentTime + 365 days;
    //     }
    // }

    // ************************ //
    // *   Solidary Regime    * //
    // ************************ //

    // -- Docs
    // -- Testing --


    // ************************ //
    // *   salvings Regime    * //
    // ************************ //

    // ************************ //
    // *   DEFI investment    * //
    // ************************ //

    // ************************ //
    // *    Overhead cost     * //
    // ************************ //

    // ************************ //
    // *       Keepers        * //
    // ************************ //

    // -- Docs
    // -- Testing --
    function updateCutoffDate() private {
        if ((block.timestamp - cutoffDate) > interval) {
            generateNewRetirentments(cutoffDate);
            cutoffDate = block.timestamp;
            MonthlyRecord storage monthlyRecord = (monthlyRecords.push());
            generalBalance[cutoffDate] = monthlyRecord;
        }
    }

    // -- Docs
    // -- Testing --
    // function setAge() public {
    //     uint256 birthday = bornAge + age;
    //     uint256 dayBeforeBirthday = block.timestamp - 1 days;
    //     uint256 dayAfterBirthday =  block.timestamp + 1 days;
    //     require(birthday > dayBeforeBirthday && birthday < dayAfterBirthday, "Doesn't your birthday");
    //     age += 1;
    // }

    function setTimeToUpdateAnnualAmount() public {
        //Todo
    }

    function withdraw(uint256 pensionId) payable public returns(bool) {
        // require(pensions[pensionId] == ownerOf(pensionId), "You don't own this pension"); // Verificar
        // require(age >= retirentment, "You don't yet of retirement age");

        // uint256 quote = quoteSolidaryRegimePension(pensionId);
        // require(quote < deposits[contributor][pensionId], "Cannot withdraw more that deposited");
        // msg.sender.transfer(quote);
        //bool output, bytes memory response) = msg.sender{value:quote, gas: 200000}("");
        // deposits[contributor][pensionId] -= quote;
        // return output;
        // // Incvompleto

    }

    // ************************ //
    // *        Utils         * //
    // ************************ //

    // -- Docs
    // -- Testing --
    function generateNewRetirentments(uint256 _cutoffDate) private {
       PensionOwner[] memory cutoffDatePensionList = cutoffDateWithdrawPensionBalance[_cutoffDate];
       for (uint256 index = 0; index > cutoffDatePensionList.length ; index++) {
           PensionOwner memory pension = cutoffDatePensionList[index];
           registerRetirentment(pension, _cutoffDate); 
       }
    }

    // -- Docs
    // -- Testing --
    function registerRetirentment(PensionOwner memory _pension, uint256 retirentmentDate) private {
        uint256 totalSavingsMoney = savingsBalance[_pension.owner][_pension.pensionId];
        uint256 totalSolidaryMoney = solidaryBalance[_pension.owner][_pension.pensionId];
        uint256 totalPensionMoney = totalSavingsMoney + totalSolidaryMoney;
        uint256 monthlyQuoteValue = ((totalPensionMoney/21)/12); 
        RetairedQuote memory newRetaired = RetairedQuote(_pension.owner, monthlyQuoteValue, quantityQuotes, 0, totalPensionMoney);
        retairedBalance[retirentmentDate].totalAmount += newRetaired.totalPension;
        retairedBalance[retirentmentDate].retairedQuotes.push(newRetaired);
    }

    // -- Docs
    // -- Testing --
    function getmonthlyBalanceFromGeneralBalance(uint256 _cutoffDate) view public returns(MonthlyRecord memory) {
        return generalBalance[_cutoffDate];
    }

    // -- Docs
    // -- Testing --
    function totalAsserts() view public returns(uint256) {
        return address(this).balance;
    }

    // -- Docs
    // -- Testing --
    function verifyIfTheContributorAlreadyMint(address _owner) public view returns(bool) {
        if(addressesThatAlreadyMinted[_owner]) { return true; }
        return false;
    }

    // -- Docs
    // -- Testing --
    function transferPension(address _to, uint256 _pensionId) public onlyOwner(_pensionId) {
        transferFrom(msg.sender, _to, _pensionId);
        ownerPensionsBalance[_pensionId] = _to;
    }

    // -- Docs
    // -- Testing --
    function determLifeExpectancyAfterRetirement(string memory _biologySex) private pure returns(uint256){
        if(compareStrings(_biologySex, "male")) {
            return maleExpectancyLife - retirentmentAge;
        } 
        if(compareStrings(_biologySex, "female")) {
            return femaleExpectancyLife - retirentmentAge;
        }
        return 0;
    }
    
    // -- Docs
    // -- Testing --
    function compareStrings(string memory a, string memory b) private pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}