#include "bsp_lcd.h"
extern const unsigned char ASCII[];


void LCD_SPI_SendData(unsigned char data)
{
	unsigned int i =0;
	LCD_CS_OFF;//拉低CS片选信号 
	for(i=0; i<8; i++ ) //在时钟线上产生八个时钟，同时把8数据一次放到数据线上
	{
		LCD_SCK_OFF;//时钟线拉低		
		if(data & 0x80) LCD_MOSI_ON;
		else            LCD_MOSI_OFF;		
		LCD_SCK_ON;//时钟线拉高		
		data <<=1;
	}
	LCD_CS_ON;//拉高CS
}

void LCD_Write_Command(unsigned char i)//写命令时需将 PB14 设为低电平
{
	LCD_RS_OFF;
	LCD_SPI_SendData(i);
}

void LCD_Write_Data(unsigned char i)//写命令时需将 PB14 设为高电平
{
	LCD_RS_ON;
	LCD_SPI_SendData(i);
}

//在屏幕上画一个点
void Draw_Point(unsigned char x, unsigned char y, unsigned int color)
{
	y += 32;
	
	LCD_Write_Command(0x2A);             
	LCD_Write_Data(0x00);             
	LCD_Write_Data(x);             

	LCD_Write_Command(0x2B);             
	LCD_Write_Data(0x00);             
	LCD_Write_Data(y);             
  	
	LCD_Write_Command(0x2c); 
	LCD_Write_Data(color>>8);             
	LCD_Write_Data(color);  	
}

void Display_Font(unsigned char Xstart,unsigned char Ystart,unsigned int Font_Color,unsigned int Background_Color,const unsigned char *Image,unsigned char num)
{
	unsigned char i,j,k,Send_Buf;

    for(i=0;i<32;i++)//打印一个32*32的汉字
	{
		for(j=0;j<4;j++) 
		{
			Send_Buf=*(Image+i*4+j+num*32*4);
			for (k=0;k<8;k++)	
			{	
		    	if(Send_Buf&(0x80>>k))	
					Draw_Point(Xstart+j*8+k,Ystart+i,Font_Color);//打印字体颜色
				else 
					Draw_Point(Xstart+j*8+k,Ystart+i,Background_Color);//打印背景颜色
			}
		}
	}
}

//全屏显示一张图片， p 为要显示的颜色值的指针,8位格式
void Display_Picture(const unsigned char *p)
{
	unsigned char i,j; 

	LCD_SetRegion(0,Row-1,0,Column-1);	//设置显示区域
	for(i=0;i<Row;i++)//行
	{
	    for(j=0;j<Column;j++)//列
		{    
			LCD_Write_Data(*(p+1));				  
			LCD_Write_Data(*p);
			p += 2;
		}
	}
}

void Display_String(unsigned char Xstart, unsigned char Ystart, unsigned int Font_Color,unsigned int Background_Color, unsigned char *string)
{
	unsigned char i,j,k;

	while(*string) 
	{	
		k=(*string)-32;
		for(i=0;i<16;i++)
		{
			for(j=0;j<8;j++) 
			{
				if(ASCII[k*16+i]&(0x80>>j))	
					Draw_Point(Xstart+j,Ystart+i,Font_Color);//打印字体颜色
				else 
					Draw_Point(Xstart+j,Ystart+i,Background_Color);//打印背景颜色
			}
		}
		Xstart+=8;
		string++;
	}
}

//对要显示的区域进行界定，写图片和纯颜色数据时要调用
void LCD_SetRegion(unsigned char Xstart,unsigned char Xend,unsigned char Ystart,unsigned char Yend)
{
	Ystart += 32;
	Yend += 32;
	
	LCD_Write_Command(0x2A);             
	LCD_Write_Data(Xstart>>8);             
	LCD_Write_Data(Xstart);             
	LCD_Write_Data(Xend>>8);             
	LCD_Write_Data(Xend);             
	
	LCD_Write_Command(0x2B);             
	LCD_Write_Data(Ystart>>8);             
	LCD_Write_Data(Ystart);             
	LCD_Write_Data(Yend>>8);             
	LCD_Write_Data(Yend);   	

	LCD_Write_Command(0x2c);
}

void Full_Display_Color(unsigned int color)//全屏显示纯颜色，color为16位的颜色数据，红绿蓝的位数：5R 6G 5B 
{
	unsigned int i,j;
	LCD_SetRegion(0,Row-1,0,Column-1);//设置显示区域

	for(i=0;i<Row;i++)
	{
	    for(j=0;j<Column;j++)
		{    
			LCD_Write_Data(color>>8);
			LCD_Write_Data(color);
		}
	}
}

void LCD_Init(void)//主要在里面完成串行模式的设置及发送复位信号让模块完成内部初始化
{ 	
	LCD_RST_OFF;//复位显示屏，在对显示屏写初始化参数之前，必须对LCD进行此操作
	HAL_Delay(100);
	LCD_RST_ON;
	HAL_Delay(50);


	LCD_Write_Command(0x11); //Exit Sleep
	HAL_Delay(50);

	LCD_Write_Command(0xB1);//Set Frame Rate
	LCD_Write_Data(0x02);
	LCD_Write_Data(0x35);
	LCD_Write_Data(0x36);

	LCD_Write_Command(0xB2);//Set Frame Rate
	LCD_Write_Data(0x02);
	LCD_Write_Data(0x35);
	LCD_Write_Data(0x36);

	LCD_Write_Command(0xB3);//Set Frame Rate
	LCD_Write_Data(0x02);
	LCD_Write_Data(0x35);
	LCD_Write_Data(0x36);
	LCD_Write_Data(0x02);
	LCD_Write_Data(0x35);
	LCD_Write_Data(0x36);
	LCD_Write_Data(0x02);
	LCD_Write_Data(0x35);
	LCD_Write_Data(0x36);

	LCD_Write_Command(0xB4);//Set Frame Rate
	LCD_Write_Data(0x03);

	LCD_Write_Command(0xC0);
	LCD_Write_Data(0xA2);
	LCD_Write_Data(0x02);
	LCD_Write_Data(0x84);
	LCD_Write_Command(0xC1);
	LCD_Write_Data(0xC5);
	LCD_Write_Command(0xC2);
	LCD_Write_Data(0x0D);
	LCD_Write_Data(0x00);
	LCD_Write_Command(0xC3);
	LCD_Write_Data(0x8D);
	LCD_Write_Data(0x2A);
	LCD_Write_Command(0xC4);
	LCD_Write_Data(0x8D);
	LCD_Write_Data(0xEE);
	//---------------------------------End ST7735S Power Sequence-------------------------------------//
	LCD_Write_Command(0xC5); //VCOM
	LCD_Write_Data(0x03);
	LCD_Write_Command(0x36); //MX, MY, RGB mode
	LCD_Write_Data(0xC8);
	//------------------------------------ST7735S Gamma Sequence-----------------------------------------//
	LCD_Write_Command(0XE0);
	LCD_Write_Data(0x12);
	LCD_Write_Data(0x1C);
	LCD_Write_Data(0x10);
	LCD_Write_Data(0x18);
	LCD_Write_Data(0x33);
	LCD_Write_Data(0x2C);
	LCD_Write_Data(0x25);
	LCD_Write_Data(0x28);
	LCD_Write_Data(0x28);
	LCD_Write_Data(0x27);
	LCD_Write_Data(0x2F);
	LCD_Write_Data(0x3C);
	LCD_Write_Data(0x00);
	LCD_Write_Data(0x03);
	LCD_Write_Data(0x03);
	LCD_Write_Data(0x10);
	LCD_Write_Command(0XE1);
	LCD_Write_Data(0x12);
	LCD_Write_Data(0x1C);
	LCD_Write_Data(0x10);
	LCD_Write_Data(0x18);
	LCD_Write_Data(0x2D);
	LCD_Write_Data(0x28);
	LCD_Write_Data(0x23);
	LCD_Write_Data(0x28);
	LCD_Write_Data(0x28);
	LCD_Write_Data(0x26);
	LCD_Write_Data(0x2F);
	LCD_Write_Data(0x3B);
	LCD_Write_Data(0x00);
	LCD_Write_Data(0x03);
	LCD_Write_Data(0x03);
	LCD_Write_Data(0x10);
	//------------------------------------End ST7735S Gamma Sequence-----------------------------------------//
	LCD_Write_Command(0x3A); //65k mode
	LCD_Write_Data(0x05);
	LCD_Write_Command(0x29); //Display on
}












