package tc;
   
   function tcbits;
      input integer tcount;
      begin
	 tcbits = $clog2(tcount)+1;
      end
   endfunction // tcbits
   
   function tcstart;
      input integer tcount;
      begin
	 tcstart = 1<<$clog2(tcount);	 
      end
   endfunction // tcstart

   function tcstop;
      input integer tcount;
      begin
	 tcstop = (1<<$clog2(tcount)) - tcount;
      end
   endfunction // tcstop
         
endpackage // tc
   
   
