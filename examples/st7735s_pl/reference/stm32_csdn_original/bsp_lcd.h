#include "stm32f1xx_hal.h"

#define Row  	128	//LCD的行数
#define Column  128	//LCD的列数  

#define RED  	0xf800
#define GREEN	0x07e0
#define BLUE 	0x001f
#define WHITE	0xffff
#define BLACK	0x0000
#define YELLOW  0xFFE0
#define GRAY0   0xEF7D   	//灰色0 3165 00110 001011 00101
#define GRAY1   0x8410      	//灰色1      00000 000000 00000
#define GRAY2   0x4208      	//灰色2  1111111111011111

//LCD屏复位引脚
#define	LCD_RST_ON   HAL_GPIO_WritePin(GPIOC, GPIO_PIN_9, GPIO_PIN_SET)
#define	LCD_RST_OFF  HAL_GPIO_WritePin(GPIOC, GPIO_PIN_9, GPIO_PIN_RESET)

//LCD屏 从机片选CS引脚
#define	LCD_CS_ON   HAL_GPIO_WritePin(GPIOB, GPIO_PIN_12, GPIO_PIN_SET)
#define	LCD_CS_OFF  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_12, GPIO_PIN_RESET)

//LCD屏 时钟信号引脚
#define	LCD_SCK_ON   HAL_GPIO_WritePin(GPIOB, GPIO_PIN_13, GPIO_PIN_SET)
#define	LCD_SCK_OFF  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_13, GPIO_PIN_RESET)

//LCD屏 写命令或写数据 控制引脚
#define	LCD_RS_ON   HAL_GPIO_WritePin(GPIOB, GPIO_PIN_14, GPIO_PIN_SET)
#define	LCD_RS_OFF  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_14, GPIO_PIN_RESET)

//LCD屏 数据输出引脚
#define	LCD_MOSI_ON   HAL_GPIO_WritePin(GPIOB, GPIO_PIN_15, GPIO_PIN_SET)
#define	LCD_MOSI_OFF  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_15, GPIO_PIN_RESET)

//LCD屏 背光控制引脚
#define	LCD_BL_ON   HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_SET)
#define	LCD_BL_OFF  HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET)



void LCD_SPI_SendData(unsigned char data);  
void LCD_Write_Command(unsigned char i); 
void LCD_Write_Data(unsigned char i);
void LCD_Init(void);
void Full_Display_Color(unsigned int color);
void LCD_SetRegion(unsigned char Xstart,unsigned char Xend,unsigned char Ystart,unsigned char Yend); 
void Draw_Point(unsigned char x, unsigned char y, unsigned int color);
void Display_Font(unsigned char Xstart,unsigned char Ystart,unsigned int Font_Color,unsigned int Background_Color,const unsigned char *Image,unsigned char num);
void Display_Picture(const unsigned char *p);
void Display_String(unsigned char Xstart, unsigned char Ystart, unsigned int Font_Color,unsigned int Background_Color, unsigned char *string);




