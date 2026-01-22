`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Penn State  
// Engineer: Michael Tufillaro
// 
// Create Date: 08/14/2024 05:07:58 PM
// Design Name: 5-Stage Pipelined Processor
// Module Name: datapath
// Project Name: Final Project
//////////////////////////////////////////////////////////////////////////////////
module datapath(
    input clk
    );
    
    //creates wires used in function calls
    wire [31:0] pc, nextPc, inst, regOut1, regOut2, imm32, aluIn2, aluOut, memOut, writeData, inst_d, regOut1_x, regOut2_x, imm32_x, aluOut_m, regOut2_m, aluOut_b, memOut_b, fMuxOutA, fMuxOutB;
    wire stall, regWrite, memToReg, memWrite, aluSrc, regDst, memRead, regWrite_x, memToReg_x, memWrite_x, aluSrc_x, regDst_x, memRead_x, regWrite_m, memToReg_m, memWrite_m, memRead_m, regWrite_b, memToReg_b;
    wire[3:0] aluControl, aluControl_x;
    wire[4:0] writeAddr, writeAddr_m, writeAddr_b, rs_x, rt_x, rd_x;
    wire[1:0] forwardA, forwardB;
    
    
    
    //Instruction Fetch Stage
    //Program counter + adder increase pc by 4 every clock cycle
    program_counter pcmodule(.clk(clk), .stall(stall), .nextPc(nextPc), .pc(pc));
    pc_adder pa(.pc(pc), .offset(32'd4), .nextPc(nextPc));
    //gets the instruction stored at pc and puts it in inst
    inst_mem im(pc, inst);
    
    
    //first pipeline- the suffix is d
    //stores the value of inst in the pipeline into inst_d
    if_id_pipeline if_id(.clk(clk), .stall(stall), .inst(inst), .inst_d(inst_d));
    
    
    //Instruction Decode Stage
    //call hazard unit to determine if a stall is needed
    hazard_unit hu(.rt_x(rt_x), .rt_d(inst_d[20:16]), .rs_d(inst_d[25:21]), .memRead_x(memRead_x), .stall(stall));
    //set control signals depending on inst
    control_unit cu(.op(inst_d[31:26]), .func(inst_d[5:0]), .aluControl(aluControl), .regWrite(regWrite), .memToReg(memToReg), .memWrite(memWrite), .aluSrc(aluSrc), .regDst(regDst), .memRead(memRead), .stall(stall));
    //Read the registers pointed to by inst and also write to registers if needed.
    register_file rf(.readAddr1(inst_d[25:21]), .readAddr2(inst_d[20:16]), .regOut1(regOut1), .regOut2(regOut2), .clk(clk), .writeAddr(writeAddr_b), .writeData(writeData), .regWrite(regWrite_b));
    //extends the immediate field of inst_d to 32 bits
    imm_extend ie(.imm(inst_d[15:0]), .imm32(imm32));
    
    
    //second pipeline goes here- the suffix is x
    id_ex_pipeline id_ex(clk, regWrite, memToReg, memWrite, aluSrc, regDst, memRead, regOut1, regOut2, imm32, inst_d[25:21], inst_d[20:16], inst_d[15:11], aluControl, regWrite_x, memToReg_x, memWrite_x, aluSrc_x, regDst_x, memRead_x, regOut1_x, regOut2_x, imm32_x, rs_x, rt_x, rd_x, aluControl_x);
    
    
    //Execution Stage
    //call forwarding unit to decide if data forwarding is necessary
    forwarding_unit fu(.writeAddr_m(writeAddr_m), .writeAddr_b(writeAddr_b), .rs_x(rs_x), .rt_x(rt_x), .regWrite_m(regWrite_m), .regWrite_b(regWrite_b), .forwardA(forwardA), .forwardB(forwardB));
    //Call muxes to pick between which three registers to use depending on the forward values
    mux_3x1_32b fMuxA(.in0(regOut1_x), .in1(writeData), .in2(aluOut_m), .sel(forwardA), .out(fMuxOutA));
    mux_3x1_32b fMuxB(.in0(regOut2_x), .in1(writeData), .in2(aluOut_m), .sel(forwardB), .out(fMuxOutB));
    //call mux with aluSrc as the selector, aluIn2 as the output, and regOut2/imm32 as the inputs
    mux_2x1_32b aluMux(.sel(aluSrc_x), .out(aluIn2), .in0(fMuxOutB), .in1(imm32_x));
    //calls alu to perform an operation with the corresonding values, stores the result in aluOut
    alu a(.aluIn1(fMuxOutA), .aluIn2(aluIn2), .aluControl(aluControl_x), .aluOut(aluOut));
    // call instMux with regDst as the selector, writeAddr as the output, and 5 bit sections of inst as the inputs
    mux_2x1_5b instMux(.sel(regDst_x), .out(writeAddr), .in0(rt_x), .in1(rd_x));
   
    
    //third pipeline goes here- the suffix is m
    ex_mem_pipeline ex_mem(clk, regWrite_x, memToReg_x, memWrite_x, memRead_x, aluOut, regOut2_x, writeAddr, regWrite_m, memToReg_m, memWrite_m, memRead_m, aluOut_m, regOut2_m, writeAddr_m);
    
    
    //Memory Stage
    //call data_mem to handle reading and writing from memory
    data_mem dm(.clk(clk), .memWrite(memWrite_m), .memRead(memRead_m), .addr(aluOut_m), .memIn(regOut2_m), .memOut(memOut));
    
    
    //fourth pipeline goes here- the suffix is b
    mem_wb_pipeline mem_wb(clk, regWrite_m, memToReg_m, aluOut_m, memOut, writeAddr_m, regWrite_b, memToReg_b, aluOut_b, memOut_b, writeAddr_b);
    
    
    //Writeback Stage
    //sets writeData to aluOut or memOut depending on memToReg
    mux_2x1_32b memMux(.sel(memToReg_b), .out(writeData), .in0(aluOut_b), .in1(memOut_b));
    
    
endmodule
/* =======================Final Project Modules========================*/
module if_id_pipeline(
    input clk, stall,
    input [31:0] inst,
    output reg [31:0] inst_d
    );
    
    //whenever the clock has a positive edge, execute this code
    always @(posedge clk) begin
        //only updates the output if stall is 1
        if (stall == 0) begin
            inst_d <= inst;
        end
    end
endmodule    
    
 module id_ex_pipeline(
    input clk, regWrite, memToReg, memWrite, aluSrc, regDst, memRead,
    input [31:0] regOut1, regOut2, imm32,
    input [4:0] rs, rt, rd,
    input [3:0] aluControl,
    output reg regWrite_x, memToReg_x, memWrite_x, aluSrc_x, regDst_x, memRead_x,
    output reg [31:0] regOut1_x, regOut2_x, imm32_x,
    output reg [4:0] rs_x, rt_x, rd_x,
    output reg [3:0] aluControl_x
    );
    
    //whenever the clock has a positive edge, execute this code
    always @(posedge clk) begin
        regWrite_x <= regWrite;
        memToReg_x <= memToReg;
        memWrite_x <= memWrite;
        aluSrc_x <= aluSrc;
        regDst_x <= regDst;
        memRead_x <= memRead;
        regOut1_x <= regOut1;
        regOut2_x <= regOut2;
        imm32_x <= imm32;
        rs_x <= rs;
        rt_x <= rt;
        rd_x <= rd;
        aluControl_x <= aluControl;
    end

endmodule

module ex_mem_pipeline(
    input clk, regWrite_x, memToReg_x, memWrite_x, memRead_x,
    input [31:0] aluOut, regOut2_x,
    input [4:0] writeAddr,
    output reg regWrite_m, memToReg_m, memWrite_m, memRead_m,
    output reg [31:0] aluOut_m, regOut2_m,
    output reg [4:0] writeAddr_m
    );
    
    //whenever the clock has a positive edge, execute this code
    always @(posedge clk) begin
        regWrite_m <= regWrite_x;
        memToReg_m <= memToReg_x;
        memWrite_m  <= memWrite_x;
        memRead_m  <= memRead_x;
        aluOut_m <= aluOut;
        regOut2_m <= regOut2_x;
        writeAddr_m <= writeAddr;
    end
endmodule    
    
 module mem_wb_pipeline(
    input clk,regWrite_m, memToReg_m,
    input [31:0] aluOut_m, memOut,
    input [4:0] writeAddr_m,
    output reg regWrite_b, memToReg_b,
    output reg [31:0] aluOut_b, memOut_b,
    output reg [4:0] writeAddr_b
    );
    
    //whenever the clock has a positive edge, execute this code
    always @(posedge clk) begin
        regWrite_b <= regWrite_m;
        memToReg_b <= memToReg_m;
        aluOut_b <= aluOut_m;
        memOut_b  <= memOut;
        writeAddr_b  <= writeAddr_m;
        
    end  
    
endmodule

module mux_3x1_32b(
    input [31:0] in0, in1, in2,
    input[1:0] sel,
    output reg [31:0] out
    );
    always @(*) begin
        // depending on the value of sel, either connect out to in0, in1, or in2
        if (sel == 0) begin
            out = in0;
        end if (sel == 1) begin
            out = in1;
        end if (sel == 2) begin
            out = in2;
        end
    end
endmodule

module forwarding_unit(
    input [4:0] writeAddr_m, writeAddr_b, rs_x, rt_x,
    input regWrite_m, regWrite_b,
    output reg [1:0] forwardA, forwardB
    );
    always @(*) begin
        //depending on the values of the inputs, determine whether a forward is needed
        if (regWrite_m && (writeAddr_m != 0) && (writeAddr_m == rs_x)) begin
            forwardA = 2'b10;
        end
        else if (regWrite_b && (writeAddr_b != 0) && (writeAddr_b == rs_x) && (!(regWrite_m && (writeAddr_m != 0) && (writeAddr_m == rs_x)))) begin
            forwardA = 2'b01;
        end else begin
            forwardA = 2'b00;
        end    
            
        if (regWrite_m && (writeAddr_m != 0) && (writeAddr_m == rt_x)) begin
            forwardB = 2'b10;
        end else if (regWrite_b && (writeAddr_b != 0) && (writeAddr_b == rt_x) && (!(regWrite_m && (writeAddr_m != 0) && (writeAddr_m == rt_x)))) begin
            forwardB = 2'b01;
        end else begin
            forwardB = 2'b00;
        end
    end
endmodule

module hazard_unit(
    input [4:0] rt_x, rt_d, rs_d,
    input memRead_x,
    output reg stall
    );
    //initialize stall to 0
    initial begin
        stall = 0;
    end
    always @(*) begin
        //if there is a load followed immediately by a use, set the stall signal to 1
        if (memRead_x && ((rt_x == rt_d)||(rt_x == rs_d))) begin
            stall = 1;
        end else begin
            stall = 0;
        end
    end
endmodule

/* ================= Modules to implement for HW1 =====================*/
module program_counter(
    input clk, stall,
    input [31:0] nextPc,
    output reg [31:0] pc
    );
    initial begin
        pc = 32'd96; // PC initialized to start from 100.
    end
    // ==================== Students fill here BEGIN ====================
    
    
    //whenever the clock has a positive edge, execute this code
    always @(posedge clk) begin
        //only updates the output if stall is 1
        if (stall == 0) begin
            //sets the pc to the nextPc value
            pc <= nextPc;
        end
    end
    
    
    // ==================== Students fill here END ======================
endmodule

module pc_adder(
    input [31:0] pc, offset,
    output reg [31:0] nextPc
    );
    // ==================== Students fill here BEGIN ====================
    
    //this code runs whenever an input changes
    always @(*) begin
        //adds the pc and offset together to find the nextPc
        nextPc = pc + offset;
    end

    // ==================== Students fill here END ======================
endmodule

/* ================= Modules to implement for HW3 =====================*/
module inst_mem(
    input [31:0] pc,
    output reg [31:0] inst
    );
    
    // This is an instruction memory that holds 64 instructions, 32b each.
    reg [31:0] memory [0:63];
    
    // Initializing instruction memory.
    initial begin       
        memory[25] = {6'b100011, 5'd0, 5'd1, 16'd0};
        memory[26] = {6'b100011, 5'd0, 5'd2, 16'd4};
        memory[27] = {6'b000000, 5'd1, 5'd2, 5'd3, 11'b00000100010};
        memory[28] = {6'b100011, 5'd3, 5'd4, 16'hFFFC};
       
        //memory[25] = {6'b100011, 5'd0, 5'd1, 16'd0};
        //memory[26] = {6'b100011, 5'd0, 5'd2, 16'd4};
        //memory[27] = {6'b100011, 5'd0, 5'd3, 16'd8};
        //memory[28] = {6'b100011, 5'd0, 5'd4, 16'd16};
        //memory[29] = {6'b000000, 5'd1, 5'd2, 5'd5, 11'b00000100000};
        //memory[30] = {6'b100011, 5'd3, 5'd6, 16'hFFFC};
        //memory[31] = {6'b000000, 5'd4, 5'd3, 5'd7, 11'b00000100010};
        
        //memory[25] = {6'b100011, 5'd0, 5'd1, 16'd0};
        //memory[26] = {6'b100011, 5'd0, 5'd2, 16'd4};
        //memory[27] = {6'b100011, 5'd0, 5'd4, 16'd16};
        //memory[28] = {6'b000000, 5'd1, 5'd2, 5'd3, 11'b00000100010};
        //memory[29] = {6'b100011, 5'd3, 5'd4, 16'hFFFC};
        
        
    end
    // ==================== Students fill here BEGIN ====================
    
    
    
    //this code runs whenever an input changes
    always @(*) begin
        // firstly, calculate pc/4: this can be accomplished by copying all but the 2 least significant digits of pc with [high:low+2], or pc[31:2]
        // then, set inst = memory[pc/4]
        inst = memory[pc[31:2]];
    end
    
    // ==================== Students fill here END ======================
endmodule

module register_file(
    input [4:0] readAddr1, readAddr2, writeAddr,
    input [31:0] writeData,
    input regWrite, clk,
    output reg [31:0] regOut1, regOut2
    );
    
    // Initializing registers. Do not touch here.
    reg [31:0] register [0:31]; // 32 registers, 32b each.
    integer i;
    initial begin
        for (i=0; i<32; i=i+1) begin
            register[i] = 32'd0; // Initialize to zero
        end
    end
    // ==================== Students fill here BEGIN ====================
    
    always @(*) begin
        //sets regOut1/2 equal to the value of the registers indicated by readAddr1/2
        regOut1 = register[readAddr1];
        regOut2 = register[readAddr2];
    end
    
    //HW 5 stuff
    //whenever the clock has a negative edge, execute this code
    always @(negedge clk) begin
        //if regWrite is 1, write the data in writeData to the storage denoted by writeAddr
        if (regWrite == 1) begin
            register[writeAddr] <= writeData;
        end
    end
    
    // ==================== Students fill here END ======================
endmodule

module control_unit(
    input [5:0] op, func,
    input stall,
    output reg regWrite, memToReg, memWrite, aluSrc, regDst, memRead,
    output reg [3:0] aluControl
    );
    // ==================== Students fill here BEGIN ====================
    always @(*) begin
        //if stall is 1, set all outputs to 0
        if (stall == 1) begin
            regWrite = 0;
            memToReg = 0;
            memWrite = 0;
            aluSrc = 0;
            regDst = 0;
            memRead = 0;
            aluControl = 4'b0;
        end else begin
            //if op is not zero, then it is either a sw or lw instruction. use switch case on op to determine which
            if (op != 0) begin
                case(op)
                    //sw
                    6'b101011: begin
                                    regWrite = 0;
                                    aluSrc = 1;
                                    aluControl = 4'b0010;
                                    memWrite = 1;
                                    memRead = 0;
                               end
                    //lw
                    6'b100011: begin
                                    regDst = 0;
                                    regWrite = 1;
                                    aluSrc = 1;
                                    aluControl = 4'b0010;
                                    memWrite = 0;
                                    memRead = 1;
                                    memToReg = 1;
                               end
                endcase
            //if op is zero, then it is either an add or sub instruction. use switch case on func to determine which
            end else begin
                case(func)
                    //add
                    6'b100000: begin
                                    regDst = 1;
                                    regWrite = 1;
                                    aluSrc = 0;
                                    aluControl = 4'b0010;
                                    memWrite = 0;
                                    memRead = 0;
                                    memToReg = 0;
                               end
                    //sub
                    6'b100010: begin
                                    regDst = 1;
                                    regWrite = 1;
                                    aluSrc = 0;
                                    aluControl = 4'b0110;
                                    memWrite = 0;
                                    memRead = 0;
                                    memToReg = 0;
                               end
                endcase
            end  
        end
    end
    // ==================== Students fill here END ======================
endmodule

/* ================= Modules to implement for HW4 =====================*/
module imm_extend(
    input [15:0] imm,
    output reg [31:0] imm32
    
    );
    // ==================== Students fill here BEGIN ====================
    
    always @(*) begin
        // If the MSB in imm is 0, fill the 16 most significant bits in imm32 with 0's
        if (imm[15] == 0) begin
            imm32[31:16] = 16'b0;
        //if the MSB is 1, fill it with 1's
        end else begin
            imm32[31:16] = 16'hffff;
        end
        //add the rest of imm to imm32
        imm32[15:0] = imm[15:0];
    end
    
    // ==================== Students fill here END ======================
endmodule

module mux_2x1_32b(
    input [31:0] in0, in1,
    input sel,
    output reg [31:0] out
    );
    // ==================== Students fill here BEGIN ====================
    
    always @(*) begin
        // depending on the value of sel, either connect out to in0 or in1
        if (sel == 0) begin
            out = in0;
        end else begin
            out = in1;
        end
    end
    
    // ==================== Students fill here END ======================
endmodule

module alu(
    input [31:0] aluIn1, aluIn2,
    input [3:0] aluControl,
    output reg [31:0] aluOut
    );

    // ==================== Students fill here BEGIN ====================
    always @(*) begin
        // depending on the value of aluControl, perform a different operation on aluIn1 and aluIn2
        //add
        if (aluControl == 4'b0010) begin
            aluOut = aluIn1 + aluIn2;
        //sub
        end if (aluControl == 4'b0110) begin
            aluOut = aluIn1 - aluIn2;
        end
    end
    // ==================== Students fill here END ======================
endmodule

module data_mem(
    input clk, memWrite, memRead,
    input [31:0] addr, memIn,
    output reg [31:0] memOut
    );
    
    reg [31:0] memory [0:63]; // 64x32 memory
    
    // Initialize data memory. Do not touch this part.
    initial begin
        memory[0] = 32'd16817;
        memory[1] = 32'd16801;
        memory[2] = 32'd16;
        memory[3] = 32'hDEAD_BEEF;
        memory[4] = 32'h4242_4242;
    end
    
    // ==================== Students fill here BEGIN ====================
    
    always @(*) begin
        if (memRead == 1) begin
            //assign the address in memory corresponding to addr/4
            memOut = memory[addr[31:2]];
        end else begin
            //make memOut filled with X's
            memOut = 32'dx;
        end
    end
    
    //whenever the clock has a negative edge, execute this code
    always @(negedge clk) begin
        //when memWrite is 1, write memIn to the memory in the spot designated by addr/4
        if (memWrite == 1) begin
            memory[addr[31:2]] <= memIn;  
        end
    end
    
    // ==================== Students fill here END ======================
endmodule

/* ================= Modules to implement for HW5 =====================*/
module mux_2x1_5b(
    input [4:0] in0, in1,
    input sel,
    output reg [4:0] out
    );
    // ==================== Students fill here BEGIN ====================
    always @(*) begin
        // depending on the value of sel, either connect out to in0 or in1
        if (sel == 0) begin
            out = in0;
        end else begin
            out = in1;
        end
    end
    
    // ==================== Students fill here END ======================
 endmodule