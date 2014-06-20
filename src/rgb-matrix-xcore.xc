/*
 * rgb-matrix-xcore.xc
 *
 *  Created on: May 17, 2014
 *      Author: lberezy
 */

#include <platform.h>
#include <xs1.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "mathuint.h"
#include "mathf8_24.h"
#include "gamma.h"
#include "rgb-matrix-xcore.h"

/**
 * Wiring
 *
 * R1   {D50}    |    G1   {D52}
 * B1   {D53}    |    _
 * R2   {D54}    |    G2   {D55}
 * B2   {D56}    |    _
 * A    {D64}    |    B    {D65}
 * C    {D66}    |    D    {D67}
 * CLK  {D10}    |    LAT  {D11}
 * OE   {D00}    |    _
 *
 * Note: OE (Output Enable) appears to be active low.
 */

/* Port mapping */

/* Output port RGB Data & LINE address 32A7-10 {A,B.C,D} 32A1-6 {R1,G1,B1,R2,G2,B2} */
 port LINE_port = XS1_PORT_32A;
/* Clock (CLK) control port {D13}*/
 port CLK_port = XS1_PORT_1C;
/* Latch (LAT) control port {D23} */
 port LAT_port = XS1_PORT_1D;
/* Output Enable (OE) port {D22} */
 port OE_port = XS1_PORT_1A;

 port Slider = XS1_PORT_8A;

int disabled = 0;


int main() {
	interface display disp;
	Slider :> void;

	par {	
		display_client(disp); 
		[[distribute]]display_server(disp);
	}
	return 0;
}



[[distributable]]
void display_server(server interface display disp) {
	pixel_t framebuffer[PANEL_WIDTH][PANEL_HEIGHT];
	LINE_port   <: 0;
	CLK_port    <: 0;
	LAT_port    <: 0;
	OE_port     <: 1;
	memset(framebuffer, 0, sizeof framebuffer);
	while(1) {
		select {
			case !disabled => disp.refresh():
				refreshDisplay(framebuffer);
				break;
			case disp.setPixel(const uint8_t x, const uint8_t y, const pixel_t pixel):
				framebuffer[y][x] = pixel;
				break;
			case disp.getPixel(const uint8_t x, const uint8_t y) -> pixel_t pixel:
				pixel = framebuffer[y][x];
				break;
		}
	}
}

void display_client(client interface display disp) {

	/* The following demo code borrowed and adapted from github skywodd/RGB_Matrix_Arduino_AVR */

	const f8_24 radius1 = 0b00010000010011001100110011001100,
							radius2 = 0b00010111000000000000000000000000,
							radius3 = 0b00101000110011001100110011001100,
							radius4 = 0b00101100001100110011001100110011,

							centerx1 = 0b00100000001100110011001100110011,
							centerx2 = 0b00010111001100110011001100110011,
							centerx3 = 0b00101110110011001100110011001100,
							centerx4 = 0b00001000001100110011001100110011,

							centery1 = 0b00010001011001100110011001100110,
							centery2 = 0b00001101000000000000000000000000,
							centery3 = 0b00011100000000000000000000000000,
							centery4 = 0b10000101110011001100110011001100,

							deltaang = 0b00000000000011110101110000101000,
							deltahue = 0b00000000001100110011001100110011;

							

		f8_24 angle1 = 0,
					angle2 = 0,
					angle3 = 0,
					angle4 = 0;

	long    hueShift =  0;

	while (1) {
		select {
			default:
				int x1, x2, x3, x4, y1, y2, y3, y4, sx1, sx2, sx3, sx4;
				uint8_t x, y;
				long value;

				sx1 = mulf8_24(cosf8_24(angle1) , radius1 + centerx1) >> MATHF8_24_BITS;
				sx2 = mulf8_24(cosf8_24(angle2) , radius2 + centerx2) >> MATHF8_24_BITS;
				sx3 = mulf8_24(cosf8_24(angle3) , radius3 + centerx3) >> MATHF8_24_BITS;
				sx4 = mulf8_24(cosf8_24(angle4) , radius4 + centerx4) >> MATHF8_24_BITS;
				y1  = mulf8_24(sinf8_24(angle1) , radius1 + centery1) >> MATHF8_24_BITS;
				y2  = mulf8_24(sinf8_24(angle2) , radius2 + centery2) >> MATHF8_24_BITS;
				y3  = mulf8_24(sinf8_24(angle3) , radius3 + centery3) >> MATHF8_24_BITS;
				y4  = mulf8_24(sinf8_24(angle4) , radius4 + centery4) >> MATHF8_24_BITS;

				for(y = 0; y < 32; y++) {
					x1 = sx1; x2 = sx2; x3 = sx3; x4 = sx4;
					for(x = 0; x < 32; x++) {
						value = hueShift
							+ (int8_t)(sinetab + (uint8_t)((x1 * x1 + y1 * y1) >> 2))
							+ (int8_t)(sinetab + (uint8_t)((x2 * x2 + y2 * y2) >> 2))
							+ (int8_t)(sinetab + (uint8_t)((x3 * x3 + y3 * y3) >> 3))
							+ (int8_t)(sinetab + (uint8_t)((x4 * x4 + y4 * y4) >> 3));
						disp.setPixel(x, y, ColorHSV(3 * value , 255, 255));

						x1--; x2--; x3--; x4--;
					}

					y1--; y2--; y3--; y4--;

				}
				disp.refresh();
				//angle1 += 0.03;
				//angle2 -= 0.07;
				angle3 += deltaang;
				//angle4 -= 0.15;
				//hueShift += 0.1;
				break;
		}

	}
}

void inline refreshDisplay(pixel_t framebuffer[PANEL_WIDTH][PANEL_HEIGHT]) {

	for (uint8_t row = 0; row < 16; row ++) { // for each row
		pixel_t* rowA = framebuffer[row];
		pixel_t* rowB = framebuffer[row + PANEL_SCANLINE_DIVISOR - 1];

		if (row == 0) {
			LAT_port <: 1; // latch data in
			LAT_port <: 0;
		}
		uint32_t M = 0xFFFFFFFF;
		uint32_t CR = 0xE1F80 | (row << 13); //3x3 leds off, shift row to ABCD pins
		for (uint8_t bit = 0; bit < RESOLUTION_BITS; bit++) { // at each bit level
			uint8_t mask = (1 << bit);

			for (uint8_t col = 0; col < 32; col++) { // clock in row of data at bit level
				uint32_t output =  ((rowB[col].b & mask ) << 6) | ((rowB[col].g & mask ) << 5) | ((rowB[col].r & mask ) << 4) | ((rowA[col].b & mask ) << 3) | ((rowA[col].g & mask ) << 2) | ((rowA[col].r & mask ) << 1);
				LINE_port <: (output | CR);
				CLK_port <: 0;
				CLK_port <: 1;
			}
			//LINE_port <: (row << 7); // send address
			LAT_port <: 1; // latch data in
			LAT_port <: 0;
			OE_port <: 0; // deassert blanking signal
			delay_microseconds(WAIT_PERIOD * (1 << (bit))); /* wait time increases as 2^bit */
			//delay_microseconds(WAIT_PERIOD * wait);
			OE_port <: 1; // assert blanking signal
		}
	}
}

/* http://en.literateprograms.org/RGB_to_HSV_color_space_conversion_%28C%29 for more info
 * The following function borrowed and modified from Adafruit RGBMatrixPanel code
 *
 *
Written by Limor Fried/Ladyada & Phil Burgess/PaintYourDragon for
Adafruit Industries.
BSD license, all text above must be included in any redistribution.
*/
inline pixel_t ColorHSV(long hue, uint8_t sat, uint8_t val) {

	uint8_t  r, g, b, lo;
	uint16_t s1, v1;
	pixel_t output;

	// Hue
	hue %= 1536;             // -1535 to +1535
	if(hue < 0) hue += 1536; //     0 to +1535
	lo = hue & 255;          // Low byte  = primary/secondary color mix
	switch(hue >> 8) {       // High byte = sextant of colorwheel
		case 0 : r = 255     ; g =  lo     ; b =   0     ; break; // R to Y
		case 1 : r = 255 - lo; g = 255     ; b =   0     ; break; // Y to G
		case 2 : r =   0     ; g = 255     ; b =  lo     ; break; // G to C
		case 3 : r =   0     ; g = 255 - lo; b = 255     ; break; // C to B
		case 4 : r =  lo     ; g =   0     ; b = 255     ; break; // B to M
		default: r = 255     ; g =   0     ; b = 255 - lo; break; // M to R
	}

	// Saturation: add 1 so range is 1 to 256, allowig a quick shift operation
	// on the result rather than a costly divide, while the type upgrade to int
	// avoids repeated type conversions in both directions.
	s1 = sat + 1;
	r  = 255 - (((255 - r) * s1) >> 8);
	g  = 255 - (((255 - g) * s1) >> 8);
	b  = 255 - (((255 - b) * s1) >> 8);

	// Value (brightness) & 16-bit color reduction: similar to above, add 1
	// to allow shifts, and upgrade to int makes other conversions implicit.
	v1 = val + 1;
	if(USE_GAMMA) { // Gamma-corrected color
		r = _gamma2[(r * v1) >> 8]; // Gamma correction table maps
		g = _gamma2[(g * v1) >> 8]; // 8-bit input to 4-bit output
		b = _gamma2[(b * v1) >> 8];
	} else { // linear (uncorrected) color
		r = (r * v1) >> 8;
		g = (g * v1) >> 8;
		b = (b * v1) >> 8;
	}

	output.r = r;
	output.g = g;
	output.b = b;
	return output;
}

