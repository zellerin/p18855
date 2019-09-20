(defun parse-hexl ()
  (let ((data (intel-hex:read-hex-from-file 655350  "~/src/p18855/core-and-oled.hex"))
	(program (make-array 65536 :element-type t)))
    (loop for i from 0 to 65535
	  do (setf (aref program i) (cons nil nil)))
    (loop for i from 0 to 65534
	  for opcode = (dpb (aref data (* i 2)) (byte 8 0)
			    (dpb (aref data (1+ (* i 2))) (byte 8 8) 0))
	  for op = (cond
		     ((case (ldb (byte 7 7) opcode)
			 (1 'movwf)
			 (3 'clrf)))
		     ((= opcode 8) 'return)
		     ((= (ldb (byte 3 11) opcode) 4) 'call)
		     ((= (ldb (byte 3 11) opcode) 5) 'goto)
		     ((= (ldb (byte 9 5) opcode) 1) 'movlb)
		     ((= (ldb (byte 6 8) opcode) #x30) 'movlw)
		     ((= (ldb (byte 6 8) opcode) #x34) 'retlw)
		     ((= (ldb (byte 4 10) opcode) #x7) 'btfss)
		     ((= (ldb (byte 4 10) opcode) #x6) 'btfsc)
		     ((= opcode 8) 'return))

	  do
	     (setf (car (aref program i))
		   (ecase op
		     ((nil) opcode)
		     ((movlb) (list op (ldb (byte 5 0) opcode)))
		     ((clrf movwf) (list op (ldb (byte 7 0) opcode)))
		     ((btfsc btfss) (list op
					  (ldb (byte 7 0) opcode)
					  (ldb (byte 3 7) opcode)))
		     ((retlw movlw) (list op (ldb (byte 8 0) opcode)))
		     (return 'return)
		     ((goto) 'goto)
		     ((call) (list 'call (aref program (ldb (byte 11 0) opcode)))))
		   (cdr (aref program i))
		   (ecase op
		     ((nil retlw movlw movwf call movlb clrf) (aref program (1+ i)))
		     ((return) nil)
		     ((goto) (aref program (ldb (byte 11 0) opcode)))
		     ((btfsc btfss)
		      (list
		       (aref program (1+ i))
		       (aref program (+ 2 i)))))))
    (aref program 0)))
