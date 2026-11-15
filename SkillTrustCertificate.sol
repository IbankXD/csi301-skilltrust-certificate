// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SkillTrustCertificate
 * @notice โจทย์ที่ 3 ระบบออกและตรวจสอบใบรับรองดิจิทัล (Blockchain Digital Certificate Verification System)
 * บริษัท SkillTrust Academy
 */
contract SkillTrustCertificate {
    address public admin;

    // สิทธิ์ของผู้ออกใบรับรอง (Authorized Issuers)
    mapping(address => bool) public authorizedIssuers;

    // 1. โครงสร้างข้อมูลหลักสูตรฝึกอบรม (Training Course)
    struct Course {
        string courseCode;
        string courseName;
        string description;
        uint256 createdAt;
        bool exists;
    }

    // 2 & 3. โครงสร้างข้อมูลใบรับรองดิจิทัล (เก็บเฉพาะรหัสอ้างอิง, Wallet, และ Hash เพื่อไม่นำข้อมูลส่วนบุคคลขึ้น Public Blockchain)
    struct Certificate {
        string certId;           // รหัสอ้างอิงใบรับรอง (ต้องไม่ซ้ำกัน)
        string courseCode;       // รหัสหลักสูตร
        address recipient;       // Wallet Address ของผู้รับใบรับรอง
        bytes32 certHash;        // ค่า Hash (keccak256) ของใบรับรองเพื่อยืนยันว่าเอกสารไม่ถูกแก้ไข
        uint256 issuedAt;        // วันที่ออกใบรับรอง (Timestamp)
        address issuer;          // ผู้ออกใบรับรอง
        bool isRevoked;          // สถานะการเพิกถอน (false = ใช้งานได้, true = ถูกเพิกถอน)
        string revokeReason;     // เหตุผลการเพิกถอน (ยังคงประวัติการออกไว้)
        uint256 revokedAt;       // เวลาที่เพิกถอน
        bool exists;
    }

    // Mappings & Arrays
    mapping(string => Course) private courses;
    string[] public courseList;

    mapping(string => Certificate) private certificates;
    string[] public certificateList;

    // 6. ประวัติใบรับรองที่ผูกกับบัญชี Wallet ของผู้เข้าอบรมแต่ละคน
    mapping(address => string[]) private recipientCertificates;

    // Events
    event IssuerAuthorized(address indexed issuer, bool status);
    event CourseCreated(string courseCode, string courseName, address indexed createdBy);
    event CertificateIssued(
        string certId,
        string courseCode,
        address indexed recipient,
        bytes32 certHash,
        uint256 issuedAt,
        address indexed issuer
    );
    event CertificateRevoked(
        string certId,
        string reason,
        uint256 revokedAt,
        address indexed revokedBy
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyAuthorizedIssuer() {
        require(
            authorizedIssuers[msg.sender] || msg.sender == admin,
            "Not an authorized certificate issuer"
        );
        _;
    }

    constructor() {
        admin = msg.sender;
        authorizedIssuers[msg.sender] = true;
        emit IssuerAuthorized(msg.sender, true);
    }

    // จัดการสิทธิ์ผู้ออกใบรับรอง (สำหรับ Admin)
    function setAuthorizedIssuer(address _issuer, bool _status) external onlyAdmin {
        require(_issuer != address(0), "Invalid address");
        authorizedIssuers[_issuer] = _status;
        emit IssuerAuthorized(_issuer, _status);
    }

    // 1. ลงทะเบียนหลักสูตร (Create Training Course)
    function createCourse(
        string memory _courseCode,
        string memory _courseName,
        string memory _description
    ) external onlyAdmin {
        require(bytes(_courseCode).length > 0, "Course code is required");
        require(bytes(_courseName).length > 0, "Course name is required");
        require(!courses[_courseCode].exists, "Course code already exists");

        courses[_courseCode] = Course({
            courseCode: _courseCode,
            courseName: _courseName,
            description: _description,
            createdAt: block.timestamp,
            exists: true
        });

        courseList.push(_courseCode);
        emit CourseCreated(_courseCode, _courseName, msg.sender);
    }

    // 2 & 3. ออกใบรับรอง (Issue Certificate) และบันทึกหลักฐาน Hash บน Blockchain (Store Certificate Hash)
    function issueCertificate(
        string memory _certId,
        string memory _courseCode,
        address _recipient,
        bytes32 _certHash
    ) external onlyAuthorizedIssuer {
        require(bytes(_certId).length > 0, "Certificate ID is required");
        require(!certificates[_certId].exists, "Certificate ID already exists");
        require(courses[_courseCode].exists, "Course does not exist");
        require(_recipient != address(0), "Invalid recipient wallet address");
        require(_certHash != bytes32(0), "Certificate hash is required");

        certificates[_certId] = Certificate({
            certId: _certId,
            courseCode: _courseCode,
            recipient: _recipient,
            certHash: _certHash,
            issuedAt: block.timestamp,
            issuer: msg.sender,
            isRevoked: false,
            revokeReason: "",
            revokedAt: 0,
            exists: true
        });

        certificateList.push(_certId);
        recipientCertificates[_recipient].push(_certId);

        emit CertificateIssued(
            _certId,
            _courseCode,
            _recipient,
            _certHash,
            block.timestamp,
            msg.sender
        );
    }

    // 4. ตรวจสอบความถูกต้อง (Verify Certificate)
    function verifyCertificate(string memory _certId)
        external
        view
        returns (
            bool isValid,
            bool exists,
            bool isRevoked,
            string memory courseCode,
            string memory courseName,
            address recipient,
            bytes32 certHash,
            uint256 issuedAt,
            address issuer,
            string memory revokeReason,
            uint256 revokedAt
        )
    {
        Certificate memory cert = certificates[_certId];
        if (!cert.exists) {
            return (false, false, false, "", "", address(0), bytes32(0), 0, address(0), "", 0);
        }

        Course memory course = courses[cert.courseCode];
        bool valid = cert.exists && !cert.isRevoked;

        return (
            valid,
            cert.exists,
            cert.isRevoked,
            cert.courseCode,
            course.courseName,
            cert.recipient,
            cert.certHash,
            cert.issuedAt,
            cert.issuer,
            cert.revokeReason,
            cert.revokedAt
        );
    }

    // ตรวจสอบว่าค่า Hash ของเอกสารตรงกับที่บันทึกบน Blockchain หรือไม่
    function verifyCertificateHash(string memory _certId, bytes32 _documentHash)
        external
        view
        returns (bool isAuthentic)
    {
        Certificate memory cert = certificates[_certId];
        if (!cert.exists || cert.isRevoked) {
            return false;
        }
        return cert.certHash == _documentHash;
    }

    // 5. เพิกถอนใบรับรอง (Revoke Certificate) โดยยังคงประวัติการออกไว้
    function revokeCertificate(string memory _certId, string memory _reason)
        external
        onlyAuthorizedIssuer
    {
        require(certificates[_certId].exists, "Certificate does not exist");
        require(!certificates[_certId].isRevoked, "Certificate is already revoked");
        require(bytes(_reason).length > 0, "Revocation reason is required");

        certificates[_certId].isRevoked = true;
        certificates[_certId].revokeReason = _reason;
        certificates[_certId].revokedAt = block.timestamp;

        emit CertificateRevoked(_certId, _reason, block.timestamp, msg.sender);
    }

    // 6. แสดงประวัติใบรับรองที่ผูกกับบัญชีของผู้เข้าอบรม (Certificate Dashboard)
    function getCertificatesByRecipient(address _recipient)
        external
        view
        returns (string[] memory)
    {
        return recipientCertificates[_recipient];
    }

    // ดึงข้อมูลหลักสูตร
    function getCourse(string memory _courseCode)
        external
        view
        returns (
            string memory courseCode,
            string memory courseName,
            string memory description,
            uint256 createdAt,
            bool exists
        )
    {
        Course memory c = courses[_courseCode];
        return (c.courseCode, c.courseName, c.description, c.createdAt, c.exists);
    }

    // ดึงจำนวนหลักสูตรและใบรับรองทั้งหมด
    function getTotalCourses() external view returns (uint256) {
        return courseList.length;
    }

    function getTotalCertificates() external view returns (uint256) {
        return certificateList.length;
    }
}
