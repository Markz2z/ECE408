// MP 5 Scan
// Given a list (lst) of length n
// Output its prefix sum = {lst[0], lst[0] + lst[1], lst[0] + lst[1] + ... + lst[n-1]}

#include    <wb.h>
#include <iostream>
#define BLOCK_SIZE 1024 //@@ You can change this

#define wbCheck(stmt) do {                                 \
        cudaError_t err = stmt;                            \
        if (err != cudaSuccess) {                          \
            wbLog(ERROR, "Failed to run stmt ", #stmt);    \
            return -1;                                     \
        }                                                  \
    } while(0)


int ceil(int a, int b){
    return (a + b - 1) / b;
}

__global__ void pscan(float * input, float * output, float* block_sum, int len) {
    //@@ Modify the body of this function to complete the functionality of
    //@@ the scan on the device
    //@@ You may need multiple kernel calls; write your kernels before this
    //@@ function and call them from here

    // for each thread, we process BLOCK_SIZE * 2 elements
    __shared__ float shared_data[BLOCK_SIZE * 2];
    int bid = blockIdx.x;
    int tid = threadIdx.x;
    int elementsNumPerBlock = BLOCK_SIZE * 2;
    int bid_offset = bid * elementsNumPerBlock;

    // ONLY FOR DEBUG
    if(tid == 0){
        printf("check bid_offset = %d\n", bid_offset);
    }
    
    // each thread load 2 elements

    if((bid_offset + 2 * tid) < len)
        shared_data[2 * tid] = input[bid_offset + 2 * tid];
    else
        shared_data[2 * tid] = 0;

    if((bid_offset + 2 * tid + 1) < len)
        shared_data[2 * tid + 1] = input[bid_offset + 2 * tid + 1];
    else
        shared_data[2 * tid + 1] = 0;

    __syncthreads();

    // up-sweep phase 

    int offset = 1;
    for(int d = elementsNumPerBlock / 2; d > 0; d /= 2){
        __syncthreads();
        if(tid < d){
            int bi = offset * 2 * (tid + 1) - 1;
            int ai = bi - offset;
            shared_data[bi] += shared_data[ai];
        }
        offset *= 2;
       
    }
    __syncthreads();


    // clear last element to zero and save it to block_sum
    if(tid == 0){
        block_sum[bid] = shared_data[elementsNumPerBlock - 1];
        shared_data[elementsNumPerBlock - 1] = 0;
    }

    __syncthreads();

    // down-sweep phase
    for(int d = 1; d < elementsNumPerBlock; d *= 2){
        offset >>= 1;
        __syncthreads();
        if(tid < d){
            int bi = offset * 2 * (tid + 1) - 1;
            int ai = bi - offset;
            float t = shared_data[ai];
            shared_data[ai] = shared_data[bi];
            shared_data[bi] += t;
        } 
        
    }

    __syncthreads();
    
    // here we get exclusive prefix sum, we add them with original data to get inclusive prefix sum
    if(bid_offset + 2 * tid < len){
        output[bid_offset + 2 * tid] = input[bid_offset + 2 * tid] + shared_data[2 * tid];
    }
    if(bid_offset + 2 * tid + 1 < len){
        output[bid_offset + 2 * tid + 1] = input[bid_offset + 2 * tid + 1] + shared_data[2 * tid + 1];
    }

}


float** g_scanBlockSums;
int maxLevel = 1;
void preallocBlockSums(unsigned int maxNumElements){
    int tempNumElements = maxNumElements;
    while(tempNumElements > 1){
        tempNumElements = ceil(tempNumElements, BLOCK_SIZE << 1);
        if(tempNumElements > 1){
            maxLevel += 1;
        }
    }

    // allocate memory for different level of blockSum
    cudaMalloc((void***) &g_scanBlockSums, sizeof(float*) * maxLevel);
    tempNumElements = maxNumElements;
    int level = 0;
    while(tempNumElements > 1){
        // this is block num
        tempNumElements = ceil(tempNumElements, BLOCK_SIZE << 1);
        cudaMalloc((void**) &g_scanBlockSums[level], sizeof(float) * tempNumElements);
        level += 1;
    }
}  
void deallocBlockSums(){
    for(int level=0; level < maxLevel; level++){
        cudaFree(g_scanBlockSums[level]);
    }
    cudaFree(g_scanBlockSums);
}

// Grid && Block are both 1-dimensional
__global__ void uniform_add(float * input, float * block_sum, int input_len){
    int block_idx = blockIdx.x;
    int thread_idx = threadIdx.x;
    int base_idx = (block_idx + 1) * (BLOCK_SIZE << 1);
    // each thread process 2 elements
    if((base_idx + 2 * thread_idx) < input_len){
        input[base_idx + 2 * thread_idx] += block_sum[block_idx - 1];
    }
    if((base_idx + 2 * thread_idx + 1) < input_len){
        input[base_idx + 2 * thread_idx + 1] += block_sum[block_idx - 1];
    }
}

// all array here are allocated on GPU
void scanRecursive(float* input, float* output, int elementNum, int level){
    int blockNum = ceil(numElements, BLOCK_SIZE << 1);
    float* scanSum;
    cudaMalloc((void**) &scanSum, sizeof(float) * blockNum);
    dim3 DimGrid(blockNum, 1, 1);
    dim3 DimBlock(BLOCK_SIZE, 1, 1);
    pscan<<<DimGrid, DimBlock>>>(input, output, g_scanBlockSums[level], elementNum);
    if(blockNum <= BLOCK_SIZE * 2){
        /*if block num is smaller than BLOCK_SIZE * 2, we just need one block to process g_blockSum*/
        dim3 blockSumGrid(1, 1, 1);
        pscan<<<blockSumGrid, DimBlock>>>(g_scanBlockSums[level], g_scanBlockSums[level], blockNum);
        
    }else{
        scanRecursive(g_scanBlockSums[level], g_scanBlockSums[level], blockNum, level + 1);
    }
    dim3 addGrid(blockNum-1, 1, 1);
    uniform_add<<<addGrid, DimBlock>>>(output, g_scanBlockSums[level], elementNum);
}



int main(int argc, char ** argv) {
    wbArg_t args;
    float * hostInput; // The input 1D list
    float * hostOutput; // The output list
    float * hostSum;
    float * deviceInput;
    float * deviceOutput;
    int numElements; // number of elements in the list

    args = wbArg_read(argc, argv);

    wbTime_start(Generic, "Importing data and creating memory on host");
    hostInput = (float *) wbImport(wbArg_getInputFile(args, 0), &numElements);
    hostOutput = (float*) malloc(numElements * sizeof(float));
    blockNum = ceil(numElements, BLOCK_SIZE << 1);
    hostSum = (float*) malloc(blockNum * sizeof(float));
    wbTime_stop(Generic, "Importing data and creating memory on host");

    wbLog(TRACE, "The number of input elements in the input is ", numElements);
    std::cout << "The number of input elements in the input is " <<numElements<<std::endl;
    wbTime_start(GPU, "Allocating GPU memory.");
    wbCheck(cudaMalloc((void**)&deviceInput, numElements*sizeof(float)));
    wbCheck(cudaMalloc((void**)&deviceOutput, numElements*sizeof(float)));
    wbCheck(cudaMalloc((void**)&deviceSum, blockNum * sizeof(float)));
    wbCheck(cudaMalloc((void**)&devicePrefixSum, blockNum * sizeof(float)));
    wbTime_stop(GPU, "Allocating GPU memory.");

    wbTime_start(GPU, "Clearing deviceSum memory.");
    wbCheck(cudaMemset(deviceOutput, 0, numElements*sizeof(float)));
    wbCheck(cudaMemset(deviceSum, 0, blockNum * sizeof(float)));
    wbCheck(cudaMemset(devicePrefixSum, 0, blockNum * sizeof(float)));
    wbTime_stop(GPU, "Clearing deviceSum memory.");
    std::cout << "deviceSum memory cleared"<<std::endl;
    wbTime_start(GPU, "Copying input memory to the GPU.");
    wbCheck(cudaMemcpy(deviceInput, hostInput, numElements*sizeof(float), cudaMemcpyHostToDevice));
    wbCheck(cudaMemcpy(deviceOutput, hostInput, numElements*sizeof(float), cudaMemcpyHostToDevice));
    wbTime_stop(GPU, "Copying input memory to the GPU.");

    //@@ Initialize the grid and block dimensions here
    dim3 DimGrid(blockNum, 1, 1);
    
    dim3 DimBlock(BLOCK_SIZE, 1, 1);
    wbTime_start(Compute, "Performing CUDA computation");
    //@@ Modify this to complete the functionality of the scan
    //@@ on the deivce
    std::cout << "Performing CUDA computation"<<std::endl;
    pscan<<<DimGrid, DimBlock>>>(deviceInput, deviceOutput, deviceSum, numElements);
    cudaDeviceSynchronize();
    std::cout << "Performing deviceSum add computation"<<std::endl;
    // add block sum to each block
    // TODO Debug
    if(blockNum > 1){

        
        dim3 DimGridAdd(blockNum-1, 1, 1);
        uniform_add<<<DimGridAdd, DimBlock>>>(deviceOutput, deviceSum, numElements);
        cudaDeviceSynchronize();
    }
    wbTime_stop(Compute, "Performing CUDA computation");
    std::cout << "Copying output memory to the CPU"<<std::endl;
    wbTime_start(Copy, "Copying output memory to the CPU");
    cudaMemcpy(hostOutput, deviceOutput, numElements*sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(hostSum, deviceSum, blockNum * sizeof(float), cudaMemcpyDeviceToHost);
    wbTime_stop(Copy, "Copying output memory to the CPU");
    std::cout << "Finished Copy output memory to the CPU"<<std::endl;


    wbTime_start(GPU, "Freeing GPU Memory");
    std::cout << "Freeing GPU Memory"<<std::endl;
    cudaFree(deviceInput);
    cudaFree(deviceOutput);
    cudaFree(deviceSum);
    wbTime_stop(GPU, "Freeing GPU Memory");
    for(int index = 0; index < blockNum; index++){
        std::cout<< hostSum[index]<<" ";
    }
    std::cout<<std::endl;

    wbSolution(args, hostOutput, numElements);

    free(hostInput);
    free(hostOutput);

    return 0;
}
