import numpy as np
'''
0.705882, 0.184314, 0.592157, 0.0509804, 0.498039,                                                                                                                  
0.584314, 0.537255, 0.117647, 0.764706, 0.141176,                                                                                                                   
0.352941, 0.223529, 0.721569, 0.247059, 0.611765,                                                                                                                   
0.686275, 0.101961, 0.694118, 0.498039, 0.345098,                                                                                                                   
0.360784, 0.0862745, 0, 0.203922, 0.141176,                                                                                                                         
check mask                                                                                                                                                          
0.0371581, 0.0734245, 0.0395363, 0.0270511, 0.00237812,                                                                                                             
0.00713436, 0.0416171, 0.0389417, 0.00891795, 0.0389417,                                                                                                            
0.0472652, 0.0749108, 0.0698573, 0.0133769, 0.062723,                                                                                                               
0.00564804, 0.0752081, 0.0719382, 0.0546968, 0.0163496,                                                                                                             
0.03478, 0.0680737, 0.0267539, 0.0157551, 0.0475624,                                                                                                                
(0, 0, 0): 0.267539                    
'''

a = np.array([
    [0.807843, 0.701961, 0.619608],
    [0.180392, 0.607843, 0.819608],
    [0.898039, 0.662745, 0.482353]
])

b = np.array([
    [0.01221, 0.0750916, 0.0222833],
    [0.023199, 0.0137363, 0.0485348],
    [0.0399878, 0.003663, 0.0586081]
])

print(a * b)