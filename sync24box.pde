/*

  clocksyncbox
  the definition of overkill

  Steve Woodward, Nov 2010

  4 clocked outputs, with individually selectable dividers from a single Sync24 input
  8 buttons
  16 LEDs

*/

//** includes

#include <EEPROM.h>
#include <NewSoftSerial.h>

//////// PINS

// sin_ = shift in
// sout_ = shift out
// dout_ = digital out
// din_  = digital in
// ain_  = analogue in
// aout_ = analogue out

// din sync input
#define DIN_SYNC_CLOCK 12
#define DIN_SYNC_RUN 13

// trigger outs
#define DOUT_TRIG_OUT_0 2
#define DOUT_TRIG_OUT_1 3
#define DOUT_TRIG_OUT_2 4
#define DOUT_TRIG_OUT_3 5

// shift ins
#define SIN_LATCHPIN 6
#define SIN_DATAPIN 7
#define SIN_CLOCKPIN 8

// datapin (blue wire)
// clock (yellow wire)
// latchpin  (green wire)

// shift outs
#define SOUT_LATCHPIN 9                            // pin connected to ST_CP of 74HC595
#define SOUT_CLOCKPIN 10                           // pin connected to SH_CP of 74HC595
#define SOUT_DATAPIN 11                            // pin connected to DS of 74HC595

#define SYNC_ZERO_CLOCK -1

// switches 
// 0 - 3 are the output selects
#define SWI_DOWN 4
#define SWI_UP 5
#define SWI_SHIFT 7




const byte total_triggers = 4;
const byte max_offset = 15;


byte trig_out_pin[total_triggers] = { DOUT_TRIG_OUT_0, 
                                      DOUT_TRIG_OUT_1, 
                                      DOUT_TRIG_OUT_2, 
                                      DOUT_TRIG_OUT_3 } ;                // pin for output
byte trig_out_divider[total_triggers] = {6,6,6,6};                       // sync divider factor
byte trig_out_offset[total_triggers] = {0,0,0,0};                        // 
boolean trig_out_state[total_triggers] = { false, false, false, false }; // is the trig on or off?
unsigned int trig_out_length[total_triggers] = {5, 5, 5, 5};             // length in milliseconds
unsigned long trig_out_time[total_triggers];                             // time last triggered
boolean trig_out_editmode[total_triggers] = {false,false,false,false};    

const byte dividersNum = 11;
byte dividers[] = {2, 3, 6, 8, 12, 16, 24, 32, 48, 72, 96, 144, 192};


long sync_trig_count = SYNC_ZERO_CLOCK;

unsigned long time;
unsigned long syncPulseTime;
unsigned long lastSyncPulseTime;
unsigned long runningSyncPulseTime;
byte tempoCount=0;


byte editMode = 0;
const byte editModeNum = 6;                        // number of edit modes (divider, offset, swing, autoreset, polarity)
byte editTrig = 0;
byte switchesA;                                    // attached to shift register
byte statusPinsA = 0;
byte statusPinsB = 0;
byte currentlyEditedTrigger = 255;                 // 255 is the off value.

byte lastSwitchStatus;        // last status of the switches


// booleans for status
boolean running = false;
boolean trig = false;
boolean trig_last = false;

void setup() {
  setup_pins();
  setup_defaults();
  updateLeds(statusPinsA, statusPinsB);
  serial_display_setup();
}


// display setup
#define SERIAL_IN 0           // not used in this
#define SERIAL_OUT 17         // analogue port 3

NewSoftSerial mySerialPort(SERIAL_IN,SERIAL_OUT);

void serial_display_setup() {
  mySerialPort.begin(9600);
  clearScreen();
  mySerialPort.print("z");
  mySerialPort.print(B00000000,BYTE);   // set to maximum brightness
}

void setup_defaults() {         
}

 
void setup_pins() {  
  // digital outs
  pinMode(DOUT_TRIG_OUT_0, OUTPUT);   
  pinMode(DOUT_TRIG_OUT_1, OUTPUT);   
  pinMode(DOUT_TRIG_OUT_2, OUTPUT);   
  pinMode(DOUT_TRIG_OUT_3, OUTPUT);   
  // digital ins
  pinMode(DIN_SYNC_CLOCK, INPUT); 
  pinMode(DIN_SYNC_RUN, INPUT);
  //shift ins
  pinMode(SIN_LATCHPIN, OUTPUT);
  pinMode(SIN_CLOCKPIN, OUTPUT); 
  pinMode(SIN_DATAPIN, INPUT);
  // shift outs
  pinMode(SOUT_LATCHPIN, OUTPUT);
  pinMode(SOUT_CLOCKPIN, OUTPUT);
  pinMode(SOUT_DATAPIN, OUTPUT);
 
}


void check_running() {
   if(digitalRead(DIN_SYNC_RUN)==HIGH) {
       running=true;
   } else {
       running=false; 
       sync_trig_count = SYNC_ZERO_CLOCK;
   }
}

void check_trig() {
   if(digitalRead(DIN_SYNC_CLOCK)==HIGH) {
       trig=true;
   } else {
       trig=false; 
   }
}


void displayDivider(int divider) {
   if(divider<=96) {
     mySerialPort.print(" ");
     mySerialPort.print(1);
     int noteLength = 96 / divider;
     display2digit(noteLength);
     mySerialPort.print("w");
     mySerialPort.print(B00010000,BYTE);  
   } if(divider>96){
     // halp
   }
 }

void display2digit(int num) {
   if(num < 10) {
    mySerialPort.print(" ");
    mySerialPort.print(num);
  } else if(num < 100) {
    mySerialPort.print(num);
  } 
}

void displayNum(int num) {
  if(num < 10) {
    mySerialPort.print("   ");
    mySerialPort.print(num);
  } else if(num < 100) {
    mySerialPort.print("  ");
    mySerialPort.print(num);
  } else if(num < 1000) {
    mySerialPort.print(" ");
    mySerialPort.print(num);
  } else {
    mySerialPort.print(num);
  }
}  


void trig_on(byte output, long sync_trig_count) { 
  sync_trig_count = sync_trig_count - (trig_out_offset[output] * 6); // handle offset, multiply by six = sixteenths
  
   if(sync_trig_count==1 || (sync_trig_count % dividers[trig_out_divider[output]])==0) {
      digitalWrite(trig_out_pin[output],1);
      trig_out_state[output] = true;
      trig_out_time[output] = millis();
      bitWrite(statusPinsA, output, 1);
      //updateLeds(statusPinsA);
    }
}

void trig_off(byte output) {
  time = millis();
  if(trig_out_state[output]==true && (time > (trig_out_time[output]+(trig_out_length[output]*dividers[trig_out_divider[output]])))) {
    digitalWrite(trig_out_pin[output],0);
    trig_out_state[output] == false;
    bitWrite(statusPinsA, output, 0);
    //updateLeds(statusPinsA);
  }
}

void all_trig_off() {
  byte count;
  for(count=0;count<total_triggers;count++) {
    digitalWrite(trig_out_pin[count],0);
    trig_out_state[count] == false;  
  }
}

 void updateLeds(byte pins) {
   digitalWrite(SOUT_LATCHPIN, LOW);
   shiftOut(SOUT_DATAPIN, SOUT_CLOCKPIN, MSBFIRST, (int)pins);  
   digitalWrite(SOUT_LATCHPIN, HIGH);
 }
 
  void updateLeds(byte pins1, byte pins2) {
   digitalWrite(SOUT_LATCHPIN, LOW);
   shiftOut(SOUT_DATAPIN, SOUT_CLOCKPIN, MSBFIRST, (int)pins2);  
   shiftOut(SOUT_DATAPIN, SOUT_CLOCKPIN, MSBFIRST, (int)pins1);  
   digitalWrite(SOUT_LATCHPIN, HIGH);
 }


byte readSwitches() {
   digitalWrite(SIN_LATCHPIN,1);
   delayMicroseconds(20); 
   digitalWrite(SIN_LATCHPIN,0);
   switchesA = shiftIn((int)SIN_DATAPIN, (int)SIN_CLOCKPIN);
}


void loop() {
   check_running();
   readSwitches();
   
   if(running==true) {
     check_trig();
     
     if(trig==true && trig_last==false) {
        sync_trig_count++;
        
        
        tempoCount++;
        lastSyncPulseTime = syncPulseTime;
        syncPulseTime = micros();
        if(tempoCount<=24) {
          runningSyncPulseTime = runningSyncPulseTime + (syncPulseTime-lastSyncPulseTime);
        } else {
          runningSyncPulseTime = 0;
          tempoCount = 0;
        }
        
        trig_on(0, sync_trig_count);
        trig_on(1, sync_trig_count);
        trig_on(2, sync_trig_count);
        trig_on(3, sync_trig_count);
        
        trig_last= true;
     }
     
     trig_off(0);
     trig_off(1);
     trig_off(2);
     trig_off(3);
     
     updateLeds(statusPinsA, statusPinsB);
     //updateLeds(statusPinsB);
     
     if(trig==false) {
      trig_last=false; 
     }
     
    // if not in edit mode, display tempo
   if(currentlyEditedTrigger==255 && tempoCount==24) {
     displayNum(calcTempo(runningSyncPulseTime));
     mySerialPort.print("w");
     mySerialPort.print(B00000000,BYTE);
   }
   
   if(currentlyEditedTrigger<255) {
     displayDivider(dividers[trig_out_divider[currentlyEditedTrigger]]);
   }
   
 
   } else {
     // stopped, so turn all triggers and LEDs off
     all_trig_off();
    // updateLeds(0);
    clearScreen();
   }
   
   editDividerModeCheck(0);
   editDividerModeCheck(1);
   editDividerModeCheck(2);
   editDividerModeCheck(3);
   
   switch (editMode) {
    case 1:
      changeDivider(0);
      changeDivider(1);
      changeDivider(2);
      changeDivider(3);
      break;
    case 2:
      changeOffset(0);
      changeOffset(1);
      changeOffset(2);
      changeOffset(3);
      break;
  }
   

   
   
   
 }
 
 
void clearScreen() {
    mySerialPort.print("v");            
    mySerialPort.print("w");
    mySerialPort.print(B00000000,BYTE);  
} 
 
 
void editDividerModeCheck(byte output) {
  if(bitRead(switchesA, output)==1 && trig_out_editmode[output]==false && bitRead(lastSwitchStatus, output)==0) {  // set to edit on
     for(int i=0;i<total_triggers; i++) {
       trig_out_editmode[i] = false;
     }
     
     trig_out_editmode[output] = true;
     int lastEditedTrigger = currentlyEditedTrigger;
     currentlyEditedTrigger = output;
     if(lastEditedTrigger!=currentlyEditedTrigger) {
       editMode = 0; 
     }
     
     bitWrite(statusPinsA, 4, 0);
     bitWrite(statusPinsA, 5, 0);
     bitWrite(statusPinsA, 6, 0);
     bitWrite(statusPinsA, 7, 0);
     bitWrite(statusPinsA, output+4, 1);
     editMode++; 
     clearEditModeLEDs();
     bitWrite(statusPinsB, editMode-1, 1);
     bitWrite(lastSwitchStatus, output, 1); 
   }
   
   if(bitRead(switchesA, output)==1 && trig_out_editmode[output]==true && editMode<editModeNum && bitRead(lastSwitchStatus, output)==0) { 
       editMode++; 
       clearEditModeLEDs();
       bitWrite(statusPinsB, editMode-1, 1);
       bitWrite(lastSwitchStatus, output, 1); 
   }
  
   if(bitRead(switchesA, output)==1 && trig_out_editmode[output]==true && editMode==editModeNum && bitRead(lastSwitchStatus, output)==0) {  // set to edit on
     clearEditModeLEDs();
     editMode=0;
     trig_out_editmode[output] = false;
     currentlyEditedTrigger = 255;
     bitWrite(statusPinsA, output+4, 0);
     bitWrite(lastSwitchStatus, output, 1); 
   }
   
    if(bitRead(switchesA, output)==0) {
     bitWrite(lastSwitchStatus, output, 0); 
   }
 
} 
 
 
void clearEditModeLEDs() {
   bitWrite(statusPinsB, 0, 0);
   bitWrite(statusPinsB, 1, 0);
   bitWrite(statusPinsB, 2, 0);
   bitWrite(statusPinsB, 3, 0);
   bitWrite(statusPinsB, 4, 0);
   bitWrite(statusPinsB, 5, 0);
}


boolean checkSwitchPress(byte swi) {
  boolean switchPressed;
  if(bitRead(switchesA, swi)==1 && bitRead(lastSwitchStatus, swi)==0) {
    switchPressed = true;
    bitWrite(lastSwitchStatus, swi, 1); 
  }
  
  if(bitRead(switchesA, swi)==0) {
     bitWrite(lastSwitchStatus, swi, 0); 
     switchPressed = false;
   }
   
  return switchPressed;
}

void changeDivider(byte output) {
   if(bitRead(switchesA, SWI_DOWN)==1  && trig_out_editmode[output]==true && bitRead(lastSwitchStatus, SWI_DOWN)==0) {
     if(trig_out_divider[output]<dividersNum-1) {
       trig_out_divider[output] = trig_out_divider[output]++;
     }
     bitWrite(lastSwitchStatus, SWI_DOWN, 1); 
   }
   
   if(bitRead(switchesA, SWI_DOWN)==0) {
     bitWrite(lastSwitchStatus, SWI_DOWN, 0); 
   }
   
   if(bitRead(switchesA, SWI_UP)==1  && trig_out_editmode[output]==true && bitRead(lastSwitchStatus, SWI_UP)==0) {
     if(trig_out_divider[output]>0) {
       trig_out_divider[output] = trig_out_divider[output]--;
     } 
     bitWrite(lastSwitchStatus, SWI_UP, 1); 
   }
   
   if(bitRead(switchesA, SWI_UP)==0) {
     bitWrite(lastSwitchStatus, SWI_UP, 0); 
   }
   
}


void changeOffset(byte output) {
   if(bitRead(switchesA, SWI_UP)==1  && trig_out_editmode[output]==true && bitRead(lastSwitchStatus, SWI_UP)==0) {
     if(trig_out_offset[output]<max_offset) {
       trig_out_offset[output] = trig_out_offset[output]++;
     }
     bitWrite(lastSwitchStatus, SWI_UP, 1); 
   }
   
   if(bitRead(switchesA, SWI_UP)==0) {
     bitWrite(lastSwitchStatus, SWI_UP, 0); 
   }
   
   if(bitRead(switchesA, SWI_DOWN)==1  && trig_out_editmode[output]==true && bitRead(lastSwitchStatus, SWI_DOWN)==0) {
     if(trig_out_offset[output]>0) {
       trig_out_offset[output] = trig_out_offset[output]--;
     } 
     bitWrite(lastSwitchStatus, SWI_DOWN, 1); 
   }
   
   if(bitRead(switchesA, SWI_DOWN)==0) {
     bitWrite(lastSwitchStatus, SWI_DOWN, 0); 
   }
   
}


 
int calcTempo(long lTimeBetweenBeats) {
   float fTimeBetweenBeats = (float) lTimeBetweenBeats; //in us
   unsigned long microSecondsInMinute = 60000000;
   return (microSecondsInMinute / fTimeBetweenBeats);
}



 
 void saveAll() {
   
 }
 

 
 
 
 ////// ----------------------------------------shiftIn function
///// just needs the location of the data pin and the clock pin
///// it returns a byte with each bit in the byte corresponding
///// to a pin on the shift register. leftBit 7 = Pin 7 / Bit 0= Pin 0

byte shiftIn(int myDataPin, int myClockPin) { 
  int i;
  int temp = 0;
  int pinState;
  byte myDataIn = 0;

//we will be holding the clock pin high 8 times (0,..,7) at the
//end of each time through the for loop

//at the begining of each loop when we set the clock low, it will
//be doing the necessary low to high drop to cause the shift
//register's DataPin to change state based on the value
//of the next bit in its serial information flow.
//The register transmits the information about the pins from pin 7 to pin 0
//so that is why our function counts down
  
  for (i=7; i>=0; i--)
  {
    digitalWrite(myClockPin, 0);
    delayMicroseconds(3);
    temp = digitalRead(myDataPin);
    
    if (temp) {
      pinState = 1;
      //set the bit to 0 no matter what
      myDataIn = myDataIn | (1 << i);
    }
 
    digitalWrite(myClockPin, 1);
  }
  return myDataIn;
}
