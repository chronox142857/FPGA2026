"""Check a sparse FPGA ILA output trace against the executed STM32 C stream."""
import argparse
import csv
import json
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]


def decode(path, reference, wait_ms=150, x_offset=2, y_offset=3, initial_color=0):
    with path.open(newline='', encoding='utf-8-sig') as handle:
        reader = csv.DictReader(handle)
        columns = reader.fieldnames
        rows = list(reader)
    def find(*names):
        for name in names:
            found = [c for c in columns if c == name or c.startswith(name+'[')]
            if len(found) == 1:
                return found[0]
        raise ValueError(f'Missing trace column {names}; found {columns}')
    ticks_col = find('debug_ticks')
    packed = next((c for c in columns if c.startswith('debug_bus[')), None)
    if not packed:
        signal_cols = [find('lcd_sck_OBUF','lcd_sck'), find('sda_in'),
                       find('lcd_dc_OBUF','lcd_dc'), find('lcd_cs_n_OBUF','lcd_cs_n'),
                       find('lcd_rst_n_OBUF','lcd_rst_n'), find('lcd_bl_OBUF','lcd_bl'),
                       find('sys_rst_n_IBUF','sys_rst_n'), find('app_rst_n_1','app_rst_n')]
    events = []
    for row in rows:
        # Vivado write_hw_ila_data CSV represents probe values in hexadecimal.
        tick = int(row[ticks_col], 16)
        bus = int(row[packed],16) if packed else sum(int(row[c],16)<<i for i,c in enumerate(signal_cols))
        if events and events[-1][1] == bus:
            continue
        events.append((tick,bus))
    assert len(events)>100, 'Too few events; capture storage qualification may be wrong'
    elapsed = lambda a,b: ((a-b)&0xffffffff)
    prev_tick,prev_bus = events[0]
    first_tick = prev_tick
    assert prev_bus&0xc0==0xc0 and prev_bus&0x3f==0, f'Capture did not start at application release: {prev_bus:02x}'
    bits = value = dc = 0
    words=[]
    cs_end=[]
    cs_start=[]
    high_cycles=[]
    low_cycles=[]
    last_rise=last_fall=None
    res_release=backlight=None
    first_clock=None
    edge_errors=[]
    for tick,bus in events[1:]:
        if bus&0x40==0 or bus&0x80==0:
            edge_errors.append('Unexpected external/application reset during trace')
        if not prev_bus&0x10 and bus&0x10:
            res_release=tick
        if not prev_bus&0x20 and bus&0x20:
            backlight=tick
        if prev_bus&8 and not bus&8:
            cs_start.append((len(words),tick))
        if not bus&8 and not prev_bus&1 and bus&1:
            if first_clock is None:
                first_clock=tick
            if bits==0:
                dc=(bus>>2)&1
            elif dc!=((bus>>2)&1):
                edge_errors.append('DC changed within byte')
            if last_fall is not None and bits>0:
                low_cycles.append(elapsed(tick,last_fall))
            value=(value<<1)|((bus>>1)&1)
            bits+=1
            last_rise=tick
        if not bus&8 and prev_bus&1 and not bus&1:
            if bits>0 and last_rise is not None:
                high_cycles.append(elapsed(tick,last_rise))
            last_fall=tick
        if not prev_bus&8 and bus&8:
            assert bits==8 and bus&1, f'Bad byte boundary: bits={bits}, bus={bus:02x}'
            words.append((dc<<8)|value)
            cs_end.append(tick)
            bits=value=0
            last_rise=last_fall=None
        prev_tick,prev_bus=tick,bus
    golden=[int(s,16) for s in reference.read_text().splitlines() if s.strip()]
    # Keep original C init/pixels; expected geometry is an explicit board profile.
    golden[78:82]=[0x100,0x100+x_offset,0x100,0x100+x_offset+127]
    golden[83:87]=[0x100,0x100+y_offset,0x100,0x100+y_offset+127]
    golden[88:]=[0x100+(initial_color>>8),0x100+(initial_color&255)]*16384
    assert len(words)>=90, f'Only {len(words)} complete bytes'
    mismatch=[i for i,(a,b) in enumerate(zip(words,golden)) if a!=b]
    assert not mismatch, f'Byte {mismatch[0]} mismatch: got {words[mismatch[0]]:03x}, expected {golden[mismatch[0]]:03x}'
    assert len(words)<=len(golden), 'Trace extends beyond the reference first frame'
    assert not edge_errors, edge_errors
    assert res_release is not None and backlight is not None
    reset_low=elapsed(res_release,first_tick)
    second_start=next(t for i,t in cs_start if i==1)
    sleep_wait=elapsed(second_start,cs_end[0])
    recovery_wait=elapsed(first_clock,res_release)
    assert abs(reset_low-5000000)<=2, f'Reset low interval {reset_low} cycles'
    wait_cycles=wait_ms*50000
    assert wait_cycles<=sleep_wait<=wait_cycles+200, f'Sleep Out interval {sleep_wait} cycles'
    # First SCK additionally includes CS idle + setup + first low half-cycle.
    assert wait_cycles<=recovery_wait<=wait_cycles+400, f'Reset recovery interval {recovery_wait} cycles'
    assert min(high_cycles)==100 and max(high_cycles)==100, 'SCK high timing mismatch'
    assert min(low_cycles)==100 and max(low_cycles)==100, 'SCK low timing mismatch'
    return {
        'event_samples':len(events), 'complete_bytes':len(words), 'trailing_bits':bits,
        'reference_prefix_equal':True, 'initialization_77_bytes_equal':True,
        'window':{'x':[x_offset,x_offset+127],'y':[y_offset,y_offset+127]},
        'initial_frame_rgb565':f'{initial_color:04x}',
        'reset_low_ms':reset_low/50000,
        'reset_release_to_first_sck_ms':recovery_wait/50000,
        'sleep_out_to_next_select_ms':sleep_wait/50000,
        'display_on_to_backlight_us':elapsed(backlight,cs_end[76])/50,
        'sck_high_us':median(high_cycles)/50, 'sck_low_us':median(low_cycles)/50,
        'first_88_words':[f'{w:03x}' for w in words[:88]],
        'span_ms':elapsed(events[-1][0],first_tick)/50000,
        'scope':'FPGA ILA output nodes and SDA input buffer; not a measurement at the screen connector',
    }


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace',nargs='?',type=Path,default=ROOT/'build/lcd_init_trace.csv')
    parser.add_argument('--wait-ms',type=int,default=150,help='50 only for historical original-C captures')
    parser.add_argument('--x-offset',type=int,default=2)
    parser.add_argument('--y-offset',type=int,default=3)
    parser.add_argument('--initial-color',type=lambda s:int(s,16),default=0,help='0000 for text clear; F800 for color cycle')
    args=parser.parse_args()
    report=decode(args.trace,ROOT/'build/sim/stm32_wire_stream.hex',args.wait_ms,args.x_offset,args.y_offset,args.initial_color)
    out=ROOT/'build/lcd_init_decoded.json'
    out.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))
