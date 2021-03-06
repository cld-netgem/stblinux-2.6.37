/* gpt.h -- GPT and data structure definitions, types, and
   functions */

/* This program is copyright (c) 2009, 2010 by Roderick W. Smith. It is distributed
  under the terms of the GNU GPL version 2, as detailed in the COPYING file. */

#include <stdint.h>
#include <sys/types.h>
#include "gptpart.h"
#include "support.h"
#include "mbr.h"
#include "bsd.h"
#include "gptpart.h"
#include "partnotes.h"

#ifndef __GPTSTRUCTS
#define __GPTSTRUCTS

#define GPTFDISK_VERSION "0.6.10"

// Constants used by GPTData::PartsToMBR(). MBR_EMPTY must be the lowest-
// numbered value to refer to partition numbers. (Most will be 0 or positive,
// of course.)
#define MBR_EFI_GPT -1
#define MBR_EMPTY -2

// Default values for sector alignment
#define DEFAULT_ALIGNMENT 2048
#define MAX_ALIGNMENT 65536

// Below constant corresponds to an 800GB disk -- a somewhat arbitrary
// cutoff
//#define SMALLEST_ADVANCED_FORMAT UINT64_C(1677721600)
// Now ~596GiB (640MB), since WD has introduced a smaller Advanced Format drive
#define SMALLEST_ADVANCED_FORMAT UINT64_C(1250263728)

using namespace std;

class PartNotes;

/****************************************
 *                                      *
 * GPTData class and related structures *
 *                                      *
 ****************************************/

// Validity state of GPT data
enum GPTValidity {gpt_valid, gpt_corrupt, gpt_invalid};

// Which set of partition data to use
enum WhichToUse {use_gpt, use_mbr, use_bsd, use_new, use_abort};

// Header (first 512 bytes) of GPT table
#pragma pack(1)
struct GPTHeader {
   uint64_t signature;
   uint32_t revision;
   uint32_t headerSize;
   uint32_t headerCRC;
   uint32_t reserved;
   uint64_t currentLBA;
   uint64_t backupLBA;
   uint64_t firstUsableLBA;
   uint64_t lastUsableLBA;
   GUIDData diskGUID;
   uint64_t partitionEntriesLBA;
   uint32_t numParts;
   uint32_t sizeOfPartitionEntries;
   uint32_t partitionEntriesCRC;
   unsigned char reserved2[GPT_RESERVED];
}; // struct GPTHeader

// Data in GPT format
class GPTData {
protected:
   struct GPTHeader mainHeader;
   GPTPart *partitions;
   uint32_t numParts;
   struct GPTHeader secondHeader;
   MBRData protectiveMBR;
   string device; // device filename
   DiskIO myDisk;
   uint32_t blockSize; // device block size
   uint64_t diskSize; // size of device, in blocks
   GPTValidity state; // is GPT valid?
   int justLooking; // Set to 1 if program launched with "-l" or if read-only
   int mainCrcOk;
   int secondCrcOk;
   int mainPartsCrcOk;
   int secondPartsCrcOk;
   int apmFound; // set to 1 if APM detected
   int bsdFound; // set to 1 if BSD disklabel detected in MBR
   uint32_t sectorAlignment; // Start & end partitions at multiples of sectorAlignment
   int beQuiet;
   WhichToUse whichWasUsed;

   int LoadHeader(struct GPTHeader *header, DiskIO & disk, uint64_t sector, int *crcOk);
   int LoadPartitionTable(const struct GPTHeader & header, DiskIO & disk, uint64_t sector = 0);
   int CheckTable(struct GPTHeader *header);
   int SaveHeader(struct GPTHeader *header, DiskIO & disk, uint64_t sector);
   int SavePartitionTable(DiskIO & disk, uint64_t sector);
public:
   // Basic necessary functions....
   GPTData(void);
   GPTData(string deviceFilename);
   virtual ~GPTData(void);

   // Verify (or update) data integrity
   int Verify(void);
   int CheckGPTSize(void);
   int CheckHeaderValidity(void);
   int CheckHeaderCRC(struct GPTHeader* header);
   void RecomputeCRCs(void);
   void RebuildMainHeader(void);
   void RebuildSecondHeader(void);
   int FindHybridMismatches(void);
   int FindOverlaps(void);
   int FindInsanePartitions(void);

   // Load or save data from/to disk
   int LoadMBR(const string & f) {return protectiveMBR.ReadMBRData(f);}
   int WriteProtectiveMBR(void) {return protectiveMBR.WriteMBRData(&myDisk);}
   void PartitionScan(void);
   int LoadPartitions(const string & deviceFilename);
   int ForceLoadGPTData(void);
   int LoadMainTable(void);
   int LoadSecondTableAsMain(void);
   int SaveGPTData(int quiet = 0, string filename = "");
   int SaveGPTBackup(const string & filename);
   int LoadGPTBackup(const string & filename);
   int SaveMBR(void);
   int DestroyGPT(void);
   int DestroyMBR(void);

   // Display data....
   void ShowAPMState(void);
   void ShowGPTState(void);
   void DisplayGPTData(void);
   void DisplayMBRData(void) {protectiveMBR.DisplayMBRData();}
   void ShowPartDetails(uint32_t partNum);

   // Convert between GPT and other formats
   virtual WhichToUse UseWhichPartitions(void);
   void XFormPartitions(void);
   virtual int XFormDisklabel(uint32_t partNum);
   int XFormDisklabel(BSDData* disklabel);
   int OnePartToMBR(uint32_t gptPart, int mbrPart); // add one partition to MBR. Returns 1 if successful
   int PartsToMBR(PartNotes & notes);

   // Adjust GPT structures WITHOUT user interaction...
   int SetGPTSize(uint32_t numEntries);
   void BlankPartitions(void);
   int DeletePartition(uint32_t partNum);
   uint32_t CreatePartition(uint32_t partNum, uint64_t startSector, uint64_t endSector);
   void SortGPT(void);
   void QuickSortGPT(int start, int finish);
   int SwapPartitions(uint32_t partNum1, uint32_t partNum2);
   int ClearGPTData(void);
   void MoveSecondHeaderToEnd();
   int SetName(uint32_t partNum, const string & theName = "");
   void SetDiskGUID(GUIDData newGUID);
   int SetPartitionGUID(uint32_t pn, GUIDData theGUID);
   void RandomizeGUIDs(void);
   int ChangePartType(uint32_t pn, uint16_t hexCode);
   void MakeProtectiveMBR(void) {protectiveMBR.MakeProtectiveMBR();}
   void RecomputeCHS(void);
   int Align(uint64_t* sector);

   // Return data about the GPT structures....
   int GetPartRange(uint32_t* low, uint32_t* high);
   int FindFirstFreePart(void);
   uint32_t GetNumParts(void) {return mainHeader.numParts;}
   uint64_t GetMainHeaderLBA(void) {return mainHeader.currentLBA;}
   uint64_t GetSecondHeaderLBA(void) {return secondHeader.currentLBA;}
   uint64_t GetMainPartsLBA(void) {return mainHeader.partitionEntriesLBA;}
   uint64_t GetSecondPartsLBA(void) {return secondHeader.partitionEntriesLBA;}
   uint64_t GetFirstUsableLBA(void) {return mainHeader.firstUsableLBA;}
   uint64_t GetLastUsableLBA(void) {return mainHeader.lastUsableLBA;}
   uint64_t GetPartFirstLBA(uint32_t i) {return partitions[i].GetFirstLBA();}
   uint64_t GetPartLastLBA(uint32_t i) {return partitions[i].GetLastLBA();}
   uint32_t CountParts(void);
   bool ValidPartNum (const uint32_t partNum);

   // Find information about free space
   uint64_t FindFirstAvailable(uint64_t start = 0);
   uint64_t FindFirstInLargest(void);
   uint64_t FindLastAvailable();
   uint64_t FindLastInFree(uint64_t start);
   uint64_t FindFreeBlocks(uint32_t *numSegments, uint64_t *largestSegment);
   int IsFree(uint64_t sector, uint32_t *partNum = NULL);
   int IsFreePartNum(uint32_t partNum);

   // Change how functions work, or return information on same
   void SetAlignment(uint32_t n);
   uint32_t ComputeAlignment(void); // Set alignment based on current partitions
   uint32_t GetAlignment(void) {return sectorAlignment;}
   void JustLooking(int i = 1) {justLooking = i;}
   void BeQuiet(int i = 1) {beQuiet = i;}
   WhichToUse WhichWasUsed(void) {return whichWasUsed;}

   // Endianness functions
   void ReverseHeaderBytes(struct GPTHeader* header);
   void ReversePartitionBytes(); // for endianness

   // Attributes functions
   int ManageAttributes(int partNum, const string & command, const string & bits);
   void ShowAttributes(const uint32_t partNum);
   void GetAttribute(const uint32_t partNum, const string& attributeBits);

}; // class GPTData

// Function prototypes....
int SizesOK(void);

#endif
