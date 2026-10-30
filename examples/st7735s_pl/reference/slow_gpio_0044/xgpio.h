#include <stdint.h>
typedef struct {unsigned unused;} XGpio;
int XGpio_Initialize(XGpio*,unsigned);
void XGpio_SetDataDirection(XGpio*,unsigned,uint32_t);
void XGpio_DiscreteWrite(XGpio*,unsigned,uint32_t);
uint32_t XGpio_DiscreteRead(XGpio*,unsigned);
