#include <stdint.h>
typedef struct {unsigned unused;} XSpi;
typedef struct {unsigned BaseAddress;} XSpi_Config;
#define XSP_MASTER_OPTION 1u
#define XSP_MANUAL_SSELECT_OPTION 2u
XSpi_Config *XSpi_LookupConfig(unsigned);
int XSpi_CfgInitialize(XSpi*,XSpi_Config*,unsigned);
int XSpi_SetOptions(XSpi*,unsigned);
void XSpi_Start(XSpi*);
void XSpi_IntrGlobalDisable(XSpi*);
int XSpi_SetSlaveSelect(XSpi*,unsigned);
int XSpi_Transfer(XSpi*,uint8_t*,uint8_t*,unsigned);
