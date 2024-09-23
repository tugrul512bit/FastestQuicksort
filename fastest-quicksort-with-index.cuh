#include<chrono>
#include<vector>
#include<iostream>
#ifndef __CUDACC__
#define __CUDACC__
#endif
#include <cuda.h>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <cuda_device_runtime_api.h>
#include <device_functions.h>
#include "helper.cuh"
namespace Quick
{
#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
	inline void gpuAssert(cudaError_t code, const char* file, int line, bool abort = true)
	{
		if (code != cudaSuccess)
		{
			fprintf(stderr, "GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
			if (abort) exit(code);
		}
	}

	__global__ void resetTasks(int* tasks, int* tasks2, int* tasks3, int* tasks4, const int n);
	 
	template<typename Type>
	__global__ void copyTasksBack(const bool trackIdValues, Type* __restrict__ data,int* __restrict__ numTasks,
		int* __restrict__ tasks, int* __restrict__ tasks2, int* __restrict__ tasks3, int* __restrict__ tasks4,
		int* __restrict__ idData,Type*__restrict__ arrTmp,int*__restrict__ idArrTmp);



	/*
		"fast" in context of how "free" a CPU core is
		this sorting is asynchronous to CPU
	*/
	template<typename Type, bool TrackIndex=true>
	struct FastestQuicksort
	{
	private:
		int deviceId;
		int compressionSupported;

		Type* data;
		bool dataCompressed;


		int* tasks;
		bool tasksCompressed;
		int* tasks2;
		bool tasks2Compressed;
		int* tasks3;
		bool tasks3Compressed;
		int* tasks4;
		bool tasks4Compressed;

		int* numTasks;
		int maxN;

		int* idData;
		bool idCompressed;

		Type* dataTmp;
		bool dataTmpCompressed;

		int* idDataTmp;
		bool idTmpCompressed;



		std::vector<Type>* toSort;
		std::vector<int>* idTracker;
		std::chrono::nanoseconds t1, t2;
		cudaStream_t stream0;

		
	public:
		FastestQuicksort(int maxElements, bool optInCompression=false)
		{
			deviceId = 0;
			maxN = maxElements;
			toSort = nullptr;
			idTracker = nullptr;
			cuInit(0);
			gpuErrchk(cudaSetDevice(0));
			gpuErrchk(cudaDeviceSynchronize());
			CUdevice currentDevice;
			auto cuErr = cuCtxGetDevice(&currentDevice);
			const char* pStr;
			if (cuGetErrorString(cuErr, &pStr) != CUDA_SUCCESS)
			{
				std::cout << "CUDA ERROR: " << pStr << std::endl;
			}
			
			
			cuErr = cuDeviceGetAttribute(&compressionSupported, CU_DEVICE_ATTRIBUTE_GENERIC_COMPRESSION_SUPPORTED, currentDevice);


			if (cuGetErrorString(cuErr, &pStr) != CUDA_SUCCESS)
			{
				std::cout << "CUDA ERROR: " << pStr << std::endl;
			}

			
			if (MemoryCompressionSuccessful())
			{
				if (optInCompression)
				{

					if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&data, maxN * sizeof(Type), true))
					{
						dataCompressed = false;
						std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;						
					}
					else
						dataCompressed = true;

					if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&dataTmp, maxN * sizeof(Type), true))
					{
						dataTmpCompressed = false;
						std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;
					}
					else
						dataTmpCompressed = true;
					

					if (TrackIndex)
					{

						if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&idData, maxN * sizeof(int), true))
						{
							idCompressed = false;
							std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;
						}
						else
							idCompressed = true;

						if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&idDataTmp, maxN * sizeof(int), true))
						{
							idTmpCompressed = false;
							std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;
						}
						else
							idTmpCompressed = true;
					}

					if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&tasks, maxN * sizeof(int), true))
					{
						tasksCompressed = false;
						std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;
					}
					else
						tasksCompressed = true;
					
					if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&tasks2, maxN * sizeof(int), true))
					{
						tasks2Compressed = false;
						std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;
					}
					else
						tasks2Compressed = true;

					if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&tasks3, maxN * sizeof(int), true))
					{
						tasks3Compressed = false;
						std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;
					}
					else
						tasks3Compressed = true;

					if (CUDA_SUCCESS != QuickHelper::allocateCompressible((void**)&tasks4, maxN * sizeof(int), true))
					{
						tasks4Compressed = false;
						std::cout << "Compressible memory failed. Trying normal allocation" << std::endl;
					}
					else
						tasks4Compressed = true;
				}
				else
				{
					dataCompressed = false;
					idCompressed = false;
					idTmpCompressed = false;
					dataTmpCompressed = false;
					tasksCompressed = false;
					tasks2Compressed = false;
					tasks3Compressed = false;
					tasks4Compressed = false;
				}
				
			}
			else
			{
				dataCompressed = false;
				idCompressed = false;
				idTmpCompressed = false;
				dataTmpCompressed = false;
				tasksCompressed = false;
				tasks2Compressed = false;
				tasks3Compressed = false;
				tasks4Compressed = false;
			}
			

			if (!dataCompressed)
				gpuErrchk(cudaMalloc(&data, maxN * sizeof(Type)));
			

			if (TrackIndex)
			{
				if (!idCompressed)			
					gpuErrchk(cudaMalloc(&idData, maxN * sizeof(int)));
				
				if (!idTmpCompressed)				
					gpuErrchk(cudaMalloc(&idDataTmp, maxN * sizeof(int)));				
			}

			
			if (cuGetErrorString(cuErr, &pStr) != CUDA_SUCCESS)
			{
				std::cout<<"CUDA ERROR: " << pStr << std::endl;
			}



			gpuErrchk(cudaStreamCreateWithFlags(&stream0,cudaStreamNonBlocking));
	
			if(!dataTmpCompressed)
				gpuErrchk(cudaMalloc(&dataTmp, maxN * sizeof(Type)));


			gpuErrchk(cudaMalloc(&numTasks, 4 * sizeof(int)));


			if(!tasksCompressed)
				gpuErrchk(cudaMalloc(&tasks, maxN * sizeof(int)));
			if (!tasks2Compressed)
				gpuErrchk(cudaMalloc(&tasks2, maxN * sizeof(int)));
			if (!tasks3Compressed)
				gpuErrchk(cudaMalloc(&tasks3, maxN * sizeof(int)));
			if (!tasks4Compressed)
				gpuErrchk(cudaMalloc(&tasks4, maxN * sizeof(int)));

			resetTasks << <1 + maxN / 1024, 1024,0,stream0 >> > (tasks, tasks2, tasks3, tasks4, maxN);
			gpuErrchk(cudaGetLastError());
			gpuErrchk(cudaDeviceSynchronize());
		}

		bool MemoryCompressionSuccessful()
		{
			return compressionSupported && dataCompressed;
		}

		// starts sorting in GPU, returns immediately
		// arrayToSort: this array is sorted by comparing its element values
		// indicesToTrack: this array's elements follow same path with arrayToSort to be used for sorting objects
		// sizes of two arrays have to be same
		void StartSorting(std::vector<Type>* arrayToSort, std::vector<int>* indicesToTrack=nullptr)
		{
			t1 = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::high_resolution_clock::now().time_since_epoch());
			toSort = arrayToSort;
			idTracker = indicesToTrack;
			int numTasksHost[4] = { 1,0,1,0 };
			int hostTasks[2] = { 0,toSort->size() - 1 };

			gpuErrchk(cudaMemcpy((void*)data, toSort->data(), toSort->size() * sizeof(Type), cudaMemcpyHostToDevice));			
			gpuErrchk(cudaMemcpy((void*)numTasks, numTasksHost, 4 * sizeof(int), cudaMemcpyHostToDevice));
			gpuErrchk(cudaMemcpy((void*)tasks2, hostTasks, 2 * sizeof(int), cudaMemcpyHostToDevice));

			if(TrackIndex && idTracker !=nullptr)
				gpuErrchk(cudaMemcpy((void*)idData, indicesToTrack->data(), indicesToTrack->size() * sizeof(int), cudaMemcpyHostToDevice));

			if (TrackIndex && idTracker != nullptr)
				copyTasksBack << <1, 1024,0,stream0 >> > (1,data, numTasks, tasks, tasks2, tasks3, tasks4,idData, dataTmp, idDataTmp);
			else
				copyTasksBack << <1, 1024, 0, stream0 >> > (0, data, numTasks, tasks, tasks2, tasks3, tasks4, idData, dataTmp, idDataTmp);

		}

		// waits for sorting to complete
		// returns elapsed time in seconds
		double Sync()
		{
			gpuErrchk(cudaStreamSynchronize(stream0));
			//gpuErrchk(cudaDeviceSynchronize());
			gpuErrchk(cudaMemcpy(toSort->data(), (void*)data, toSort->size() * sizeof(Type), cudaMemcpyDeviceToHost));
			if (TrackIndex && idTracker != nullptr)
				gpuErrchk(cudaMemcpy(idTracker->data(), (void*)idData, idTracker->size() * sizeof(int), cudaMemcpyDeviceToHost));
			t2 = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::high_resolution_clock::now().time_since_epoch());
			toSort = nullptr;
			idTracker = nullptr;
			return (t2.count() - t1.count()) / 1000000000.0;
		}

		~FastestQuicksort()
		{
			if (dataCompressed)
			{
				if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)data, maxN * sizeof(Type), true))
				{
					std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
					gpuErrchk(cudaFree(data));
				}
			}
			else
				gpuErrchk(cudaFree(data));
			
			if (dataCompressed)
			{
				if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)dataTmp, maxN * sizeof(Type), true))
				{
					std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
					gpuErrchk(cudaFree(dataTmp));
				}
			}
			else
				gpuErrchk(cudaFree(dataTmp));
			

			if (tasksCompressed)
			{
				if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)tasks, maxN * sizeof(int), true))
				{
					std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
					gpuErrchk(cudaFree(tasks));
				}
			}
			else
				gpuErrchk(cudaFree(tasks));


			if (tasks2Compressed)
			{
				if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)tasks2, maxN * sizeof(int), true))
				{
					std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
					gpuErrchk(cudaFree(tasks2));
				}
			}
			else
				gpuErrchk(cudaFree(tasks2));



			if (tasks3Compressed)
			{
				if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)tasks3, maxN * sizeof(int), true))
				{
					std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
					gpuErrchk(cudaFree(tasks3));
				}
			}
			else
				gpuErrchk(cudaFree(tasks3));



			if (tasks4Compressed)
			{
				if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)tasks4, maxN * sizeof(int), true))
				{
					std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
					gpuErrchk(cudaFree(tasks4));
				}
			}
			else
				gpuErrchk(cudaFree(tasks4));


			gpuErrchk(cudaFree(numTasks));


			if (TrackIndex)
			{
				if (idCompressed)
				{
					if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)idData, maxN * sizeof(int), true))
					{
						std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
						gpuErrchk(cudaFree(idData));
					}
				}
				else
					gpuErrchk(cudaFree(idData));

				if (idTmpCompressed)
				{
					if (CUDA_SUCCESS != QuickHelper::freeCompressible((void*)idDataTmp, maxN * sizeof(int), true))
					{
						std::cout << "Compressible memory-free failed. Trying normal deallocation" << std::endl;
						gpuErrchk(cudaFree(idDataTmp));
					}
				}
				else
					gpuErrchk(cudaFree(idDataTmp));
			}
			
			

			gpuErrchk(cudaStreamDestroy(stream0));
		}
	};



	class Bench
	{
	public:
		Bench(size_t* targetPtr)
		{
			target = targetPtr;
			t1 = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::high_resolution_clock::now().time_since_epoch());
			t2 = t1;
		}

		~Bench()
		{
			t2 = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::high_resolution_clock::now().time_since_epoch());
			if (target)
			{
				*target = t2.count() - t1.count();
			}
			else
			{
				std::cout << (t2.count() - t1.count()) / 1000000000.0 << " seconds" << std::endl;
			}
		}
	private:
		size_t* target;
		std::chrono::nanoseconds t1, t2;
	};
}