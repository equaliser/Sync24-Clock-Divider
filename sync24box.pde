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

// switches 
// 0 - 3 are the output selects
#define SWI_DOWN 4
#define SWI_UP 5
#define SWI_SHIFT 7


#define SYNC_ZERO_CLOCK -1



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
boolean trig_out_polarity[total_triggers] = {true,true,true,true};       // polarity of trigger, true = pos, false = short
int trig_out_swing[total_triggers] = {0,0,0,0};
int trig_out_autoreset[total_triggers] = {0,0,0,0};
long trig_sync_trig_count[total_triggers] = {SYNC_ZERO_CLOCK, SYNC_ZERO_CLOCK, SYNC_ZERO_CLOCK, SYNC_ZERO_CLOCK};
boolean trig_out_muted[total_triggers] = {false,false,false,false};
byte trig_out_random[total_triggers] = {0,0,0,0};
const byte dividersNum = 15;
int dividers[] = {2, 3, 6, 8, 12, 16, 24, 32, 48, 72, 96, 144, 192, 288, 384};
int autoreset_divisions[] = {0, 48, 96, 144, 192};

long sync_trig_count = SYNC_ZERO_CLOCK;

unsigned long time;
unsigned long syncPulseTime;
unsigned long lastSyncPulseTime;
unsigned long runningSyncPulseTime;
byte tempoCount=0;


byte editMode = 0;
const byte editModeNum = 6;                        // number of edit modes (divider, offset, swing, autoreset, polarity, x)

byte switchesA;                                    // attached to shift register
byte lastSwitchStatus;                             // last status of the switches

byte statusPinsA = 0;                              // first set of 8 LEDs
byte statusPinsB = 0;                              // second set of 8 LEDs
byte currentlyEditedTrigger = 255;                 // 255 is the off value.
byte lastEditedTrigger = 254;

// booleans for status
boolean running = false;
boolean trig = false;
boolean trig_last = false;

void setup() {
  randomSeed(analogRead(0));
  setup_pins();
  updateLeds(statusPinsA, statusPinsB);
  serial_display_setup();
}


// display setup
#define SERIAL_IN 0           // not used in this
#define SERIAL_OUT 17         // analogue port 3

NewSoftSerial mySerialPort(SERIAL_IN,SERIAL_OUT);

void serial_display_setup() {
  mySerialPort.begin(57600);
  delay(500);
  mySerialPort.print("v");
  mySerialPort.print(B01111111,BYTE);  
  mySerialPort.print(B00000110,BYTE); 
  delay(500);
  clearScreen();
  mySerialPort.print("z");
  mySerialPort.print(B00000000,BYTE);   // set to maximum brightness
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
       trig_sync_trig_count[0] = SYNC_ZERO_CLOCK;
       trig_sync_trig_count[1] = SYNC_ZERO_CLOCK;
       trig_sync_trig_count[2] = SYNC_ZERO_CLOCK;
       trig_sync_trig_count[3] = SYNC_ZERO_CLOCK;
   }
}

void check_trig() {
   if(digitalRead(DIN_SYNC_CLOCK)==HIGH) {
       trig=true;
   } else {
       trig=false; 
   }
}

// *display

void displayDivider(int divider) {
   if(divider<=96) {
     mySerialPort.print(" ");
     mySerialPort.print(1);
     int noteLength = 96 / divider;
     display2digit(noteLength);
     mySerialPort.print("w");
     mySerialPort.print(B00010000,BYTE);       // print colon
   } else {
     int denominator = divider / 96;
     mySerialPort.print(" ");
     mySerialPort.print(denominator);
     mySerialPort.print(" ");
     mySerialPort.print(1);
   }
 }
 
 void displayOffset(int offset) {
     if(offset<10) {
       mySerialPort.print(" ");
       mySerialPort.print(offset);
     } else {
       mySerialPort.print(offset);
     }
     mySerialPort.print(16);          // offset denominator
     mySerialPort.print("w");
     mySerialPort.print(B00010000,BYTE);  
 }
 
 void displaySwing(int swing) {
   clearScreen();
 }
 
 void displayAutoreset(int autoreset) {
   if(autoreset==0) {
     mySerialPort.print(" off");
     mySerialPort.print("w");
     mySerialPort.print(B00000000,BYTE);       // clear
   } else {
     displayDivider(autoreset);
   }
 }
 
 void displayPolarity(boolean polarity) {
   if(polarity==true) {
     mySerialPort.print(" POS");
   } else {
     mySerialPort.print("SHRT");
   }
 }
 
 void displayRandomGate(byte threshold) {
   if(threshold==0) {
     mySerialPort.print(" off");
   } else {
     mySerialPort.print("  ");
     display2digit((int)threshold);
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


// *trig

void trig_on(byte output, long sync_trig_count) { 
  sync_trig_count = sync_trig_count - (trig_out_offset[output] * 6); // handle offset, multiply by six = sixteenths
  if(trig_out_muted[output]==false && sync_trig_count>0 && randomGate(output)==true) {
     if(sync_trig_count==1 || (sync_trig_count % dividers[trig_out_divider[output]])==0) {
        digitalWrite(trig_out_pin[output],trig_out_polarity[output]);
        trig_out_state[output] = true;
        trig_out_time[output] = millis();
        bitWrite(statusPinsA, output, 1);
      }
  }
}

void trig_off(byte output) {
  time = millis();
  if(trig_out_state[output]==true && (time > (trig_out_time[output]+(trig_out_length[output]*dividers[trig_out_divider[output]])))) {
    digitalWrite(trig_out_pin[output],!trig_out_polarity[output]);
    trig_out_state[output] == false;
    bitWrite(statusPinsA, output, 0);
  }
}

void all_trig_off() {
  byte count;
  for(count=0;count<total_triggers;count++) {
    digitalWrite(trig_out_pin[count],!trig_out_polarity[count]);
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
        trig_sync_trig_count[0]++;
        trig_sync_trig_count[1]++;
        trig_sync_trig_count[2]++;
        trig_sync_trig_count[3]++;
        
        tempoCount++;
        lastSyncPulseTime = syncPulseTime;
        syncPulseTime = micros();
        if(tempoCount<=24) {
          runningSyncPulseTime = runningSyncPulseTime + (syncPulseTime-lastSyncPulseTime);
        } else {
          runningSyncPulseTime = 0;
          tempoCount = 0;
        }
        
        trig_on(0, trig_sync_trig_count[0]);
        trig_on(1, trig_sync_trig_count[1]);
        trig_on(2, trig_sync_trig_count[2]);
        trig_on(3, trig_sync_trig_count[3]);
        
        trig_last= true;
     }
     
     trig_off(0);
     trig_off(1);
     trig_off(2);
     trig_off(3);
     
     
     if(trig==false) {
      trig_last=false; 
     }
     
      // if not in edit mode, display tempo
     if(editMode==0 && tempoCount==24) {
       displayNum(calcTempo(runningSyncPulseTime));
       mySerialPort.print("w");
       mySerialPort.print(B00000000,BYTE);
     }

   } else {
     // stopped, so turn all triggers and LEDs off
     all_trig_off();
     clearScreen();
     clearTrigLEDs();
   }
   
   updateLeds(statusPinsA, statusPinsB);
   
   editModeCheck(0);
   editModeCheck(1);
   editModeCheck(2);
   editModeCheck(3);
   
   changeMute(0);
   changeMute(1);
   changeMute(2);
   changeMute(3);
   
   autoReset(0);
   autoReset(1);
   autoReset(2);
   autoReset(3);
   
   switch (editMode) {
    case 1:
      changeDivider(0);
      changeDivider(1);
      changeDivider(2);
      changeDivider(3);
      displayDivider(dividers[trig_out_divider[currentlyEditedTrigger]]);
      break;
    case 2:
      changeOffset(0);
      changeOffset(1);
      changeOffset(2);
      changeOffset(3);
      displayOffset(trig_out_offset[currentlyEditedTrigger]);
      break;
    case 3:
      // do swing
      displaySwing(trig_out_swing[currentlyEditedTrigger]);
      break;
    case 4:
      // do autoreset
      changeAutoreset(0);
      changeAutoreset(1);
      changeAutoreset(2);
      changeAutoreset(3);
      displayAutoreset(autoreset_divisions[trig_out_autoreset[currentlyEditedTrigger]]);
      break;
    case 5:
      // do polarity change
      changePolarity(0);
      changePolarity(1);
      changePolarity(2);
      changePolarity(3);
      displayPolarity(trig_out_polarity[currentlyEditedTrigger]);
      break;
    case 6:
      for(int i=0;i<total_triggers;i++) {
        changeRandomGate(i);
      }
      displayRandomGate(trig_out_random[currentlyEditedTrigger]);
      break;
  }
 }
 
 
void clearScreen() {
    mySerialPort.print("v");            
    mySerialPort.print("w");
    mySerialPort.print(B00000000,BYTE);  
} 
 
 
void editModeCheck(byte output) {
  if(bitRead(switchesA, output)==1 && checkShifted()==false && bitRead(lastSwitchStatus, output)==0 && trig_out_editmode[output]==false && lastEditedTrigger!=currentlyEditedTrigger) {  // set to edit on
     for(int i=0;i<total_triggers; i++) {
       trig_out_editmode[i] = false;
     }
     
     lastEditedTrigger = currentlyEditedTrigger;
     currentlyEditedTrigger = output;
     
     trig_out_editmode[output] = true;
     
    
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
   
   if(bitRead(switchesA, output)==0) {
       bitWrite(lastSwitchStatus, output, 0); 
   }
   
   if(bitRead(switchesA, output)==1  && checkShifted()==false && bitRead(lastSwitchStatus, output)==0 && trig_out_editmode[output]==true && editMode<editModeNum) { 
       editMode++; 
       clearEditModeLEDs();
       bitWrite(statusPinsB, editMode-1, 1);
       bitWrite(lastSwitchStatus, output, 1); 
   }
  
   if(bitRead(switchesA, output)==1  && checkShifted()==false && bitRead(lastSwitchStatus, output)==0 && trig_out_editmode[output]==true && editMode==editModeNum) {  // set to edit on
     clearEditModeLEDs();
     editMode=0;
     trig_out_editmode[output] = false;
     currentlyEditedTrigger = 255;
     lastEditedTrigger = 254;
     bitWrite(statusPinsA, output+4, 0);
     bitWrite(lastSwitchStatus, output, 1); 
   }
 
} 
 
void clearTrigLEDs() {  
   bitWrite(statusPinsA, 0, 0);
   bitWrite(statusPinsA, 1, 0);
   bitWrite(statusPinsA, 2, 0);
   bitWrite(statusPinsA, 3, 0);
} 
 
 
void clearEditModeLEDs() {
   bitWrite(statusPinsB, 0, 0);
   bitWrite(statusPinsB, 1, 0);
   bitWrite(statusPinsB, 2, 0);
   bitWrite(statusPinsB, 3, 0);
   bitWrite(statusPinsB, 4, 0);
   bitWrite(statusPinsB, 5, 0);
}

// switchchecks

boolean checkSwitchPressed(byte swi) {
  if(bitRead(switchesA, swi)==1  && bitRead(lastSwitchStatus, swi)==0) {
    bitWrite(lastSwitchStatus, swi, 1); 
    return true;
  } else {
    return false; 
  }
}

void checkSwitchUp(byte swi) {
   if(bitRead(switchesA, swi)==0) {
       bitWrite(lastSwitchStatus, swi, 0); 
   }
}

boolean checkShifted() {
  if(bitRead(switchesA, SWI_SHIFT)==1) {
    return true;
  }  else {
    return false;
  }
}


// dochanges

void changeDivider(byte output) {  
   if(trig_out_editmode[output]==true) {  
     if(checkSwitchPressed(SWI_DOWN)==true) {
       if(trig_out_divider[output]<dividersNum-1) {
         trig_out_divider[output] = trig_out_divider[output]++;
       }
     }
     checkSwitchUp(SWI_DOWN);
          
     if(checkSwitchPressed(SWI_UP)==true) {
       if(trig_out_divider[output]>0) {
         trig_out_divider[output] = trig_out_divider[output]--;
       }
     }
     checkSwitchUp(SWI_UP);
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

void changePolarity(byte output) {
  if(checkSwitchPressed(SWI_DOWN)==true) {
    trig_out_polarity[output] = !trig_out_polarity[output];
  }
  
  checkSwitchUp(SWI_DOWN);
  
  if(checkSwitchPressed(SWI_UP)==true) {
    trig_out_polarity[output] = !trig_out_polarity[output];
  }
  
  checkSwitchUp(SWI_UP);  
}

void changeMute(byte output) {
  if(checkSwitchPressed(output) && checkShifted()==true) {
    trig_out_muted[output] = !trig_out_muted[output];
  }
  
  checkSwitchUp(output);
}

void changeAutoreset(byte output) {
   if(trig_out_editmode[output]==true) {  
     if(checkSwitchPressed(SWI_UP)==true) {
       if(trig_out_autoreset[output]<(sizeof(autoreset_divisions)/sizeof(int))-1) {
         trig_out_autoreset[output] = trig_out_autoreset[output]++;
       }
     }
     checkSwitchUp(SWI_UP);
          
     if(checkSwitchPressed(SWI_DOWN)==true) {
       if(trig_out_autoreset[output]>0) {
         trig_out_autoreset[output] = trig_out_autoreset[output]--;
       }
     }
     checkSwitchUp(SWI_DOWN);
   }
}

void changeRandomGate(byte output) {
    if(trig_out_editmode[output]==true) {  
      if(checkSwitchPressed(SWI_UP)==true) {
       if(trig_out_random[output]<10) {
         trig_out_random[output] = trig_out_random[output]++;
       }
     }
     checkSwitchUp(SWI_UP);
          
     if(checkSwitchPressed(SWI_DOWN)==true) {
       if(trig_out_random[output]>0) {
         trig_out_random[output] = trig_out_random[output]--;
       }
     }
     checkSwitchUp(SWI_DOWN);
   }
}


// randomGate
// returns true if the output should be triggered
boolean randomGate(byte output) {
  if(trig_out_random[output]>0) {
    int randNumber = random(10);
    if(randNumber>=trig_out_random[output]) {
      return false;
    }
  }
  return true;
}



void autoReset(byte output) {
  if(autoreset_divisions[trig_out_autoreset[output]]!=0 && trig_sync_trig_count[output]>0) {
    if(autoreset_divisions[trig_out_autoreset[output]]==trig_sync_trig_count[output]) {
      trig_sync_trig_count[output]=0;
    }
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
