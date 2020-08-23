extern crate ocl;
extern crate rand;

use ocl::{ProQue, OclCoreError, OclPrm, Buffer, Platform, Device, flags};
use std::num::Wrapping;
use std::ops::AddAssign;
use std::str;
use std::fs::File;
use std::io::Read;
use ocl::enums::PlatformInfo;
use ocl::core::{DEVICE_TYPE_GPU, ContextProperties, ArgVal, MEM_COPY_HOST_PTR};
use ocl::core;
use std::borrow::Borrow;
use std::any::Any;
use std::ffi::CString;
use std::fmt::{Debug, Formatter, Error, LowerHex};
//use ocl::core::types::enums::EmptyInfoResultError::Context;
use ocl::core::Context;
use std::str::from_utf8;

fn main() {
    let h0 : u32 = 0x67452301;
    let h1 : u32 = 0xEFCDAB89;
    let h2 : u32 = 0x98BADCFE;
    let h3 : u32 = 0x10325476;
    let h4 : u32 = 0xC3D2E1F0;
    let m = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let bytes: Vec<u8>= m.bytes().into_iter().collect();
    let bits_len: u32 = (bytes.len() * 8) as u32;
    assert_eq!(bits_len % 512, 0);

    // convert to chunks, which internally split data in 16 32bits-numbers and extend them to 80 32bits-numbers
    // the given bytes' size should be a multiple of 512 bits here
    let chunks = Chunk::from_bytes(bytes);
    // initial values for sha-1
    let mut result = ResultSha1::new(h0, h1, h2, h3, h4);
    for chunk in chunks {
        result += main_operation_sha1(chunk, result);
    }
    println!();
    print!("{}", m);
    let suffix = explore_sha1_ocl(result, 9, bits_len).unwrap();
//    print!("{}", m);
    for chunk in suffix{
//        for byte in chunk.as_u8().iter() {
//            print!("{:x} ", byte);
//        }
        print!("{}", from_utf8(&chunk.as_u8()).unwrap());
    }
    println!();
}



//fn find_hash_value(authdata: &str, difficulty: u32){
//fn find_hash_value(authdata: Vec<u32>, difficulty: u32) {
//    for platform in Platform::list(){
//        println!("{}", platform.info(PlatformInfo::Name).unwrap());
//        for device in Device::list_all(platform).unwrap(){
//            println!("{}", device.name().unwrap());
//        }
//    }
//    let mut file = File::open("src/kernel.cl").unwrap();
//    let mut src = String::new();
//    file.read_to_string(&mut src).unwrap();
//
//    // (1) Create an all-in-one context, program, command queue, and work /
//    // buffer dimensions:
//    let pro_que = ProQue::builder()
//        .src(src)
//        .dims(3072)
////        .dims(200)
//        .build().unwrap();
//
//    // (2) Create a `Buffer`:
//    let buffer = pro_que.create_buffer::<u32>().unwrap();
//    let result = pro_que.create_buffer::<u32>().unwrap();
//    let finished = Buffer::builder().queue(pro_que.queue().clone()).len(1).fill_val(0u8).build().unwrap();
////    let finished = pro_que.create_buffer::<u8>().unwrap();
//
//    let test = IntResult { a: 35, b: 0, c: 0, d: 0, e: 0 };
//    // (3) Create a kernel with arguments matching those in the source above:
//    let kernel = pro_que.kernel_builder("sha1_step")
//        .arg(&buffer)
//        .arg(&result)
//        .arg(&finished)
//        .arg(&test)
//        .arg(difficulty)
//        .build().unwrap();
//    unsafe { kernel.enq().unwrap() }
//
//    let mut vec = vec![0u32; buffer.len()];
//    buffer.read(&mut vec).enq();
//
//    println!("idx {} value {}", 200, vec[200]);
//}






fn explore_sha1_ocl(initial_r : ResultSha1, difficulty: u8, bit_len: u32) -> ocl::Result<Vec<Chunk>> {

    let mut file = File::open("src/kernel.cl").unwrap();
    let mut src = String::new();
    file.read_to_string(&mut src).unwrap();
//    let src = r#"
//        __kernel void add(__global float* buffer, float scalar) {
//            buffer[get_global_id(0)] += scalar;
//        }
//    "#;

    // (1) Define which platform and device(s) to use. Create a context,
    // queue, and program then define some dims (compare to step 1 above).
//    let mut platform = Platform::list()
//        .into_iter()
//        .filter(|p| Device::list_select(p, Some(DEVICE_TYPE_GPU), &[0] ).unwrap_or(Vec::new()).len() != 0)
//        .next()
//        .unwrap();

      // (1) Define which platform and device(s) to use. Create a context,
    // queue, and program then define some dims..
    let platforms = core::get_platform_ids().unwrap();
    let platform_id = platforms.into_iter()
        .filter(|p| core::get_device_ids(p, Some(DEVICE_TYPE_GPU), None).unwrap_or(Vec::new()).len() != 0)
        .next()
        .unwrap();
    let device_ids = core::get_device_ids(&platform_id, Some(DEVICE_TYPE_GPU), None).unwrap();
    let device_id = device_ids[0];
    let context_properties = ContextProperties::new().platform(platform_id);
    let context = core::create_context(Some(&context_properties),
        &[device_id], None, None).unwrap();
    let src_cstring = CString::new(src).unwrap();
    let program = core::create_program_with_source(&context, &[src_cstring]).unwrap();
    core::build_program(&program, Some(&[device_id]), &CString::new("").unwrap(),
        None, None).unwrap();
    let queue = core::create_command_queue(&context, &device_id, None).unwrap();
    let dims = [10, 1, 1];

    // (2) Create a `Buffer`:
//    let mut vec = vec![12; dims[0]];
//    let mut vec = vec![1,2,3,4];
    let random_chunks = Chunk::generateRandomChunks(dims[0] as u32);
    let random_chunks = unsafe { core::create_buffer(&context, flags::MEM_READ_ONLY |
        flags::MEM_COPY_HOST_PTR, dims[0], Some(&random_chunks)).unwrap() };
    let finished = unsafe { core::create_buffer(&context, flags::MEM_READ_WRITE |
        MEM_COPY_HOST_PTR, 1, Some(&[0u8])).unwrap() };
    // we assume 64 chunks will do
    let mut result_host = vec![Chunk::default(); 32];
    let result = unsafe { core::create_buffer(&context, flags::MEM_WRITE_ONLY | flags::MEM_COPY_HOST_PTR, 32, Some(&result_host)).unwrap() };

    // (3) Create a kernel with arguments matching those in the source above:
    let kernel = core::create_kernel(&program, "explore_sha1").unwrap();
    core::set_kernel_arg(&kernel, 0, ArgVal::scalar(&difficulty)).unwrap();
    core::set_kernel_arg(&kernel, 1, ArgVal::mem(&random_chunks)).unwrap();
    core::set_kernel_arg(&kernel, 2, ArgVal::vector(&initial_r)).unwrap();
    core::set_kernel_arg(&kernel, 3, ArgVal::scalar(&bit_len)).unwrap();
    core::set_kernel_arg(&kernel, 4, ArgVal::mem(&finished)).unwrap();
    core::set_kernel_arg(&kernel, 5, ArgVal::mem(&result)).unwrap();

    // (4) Run the kernel:
    unsafe { core::enqueue_kernel(&queue, &kernel, 1, None, &dims,
        None, None::<core::Event>, None::<&mut core::Event>).unwrap(); }

    // (5) Read results from the device into a vector:
    unsafe { core::enqueue_read_buffer(&queue, &result, true, 0, &mut result_host,
        None::<core::Event>, None::<&mut core::Event>)?; }

    let mut valid_chunks: Vec<_> = result_host.into_iter()
        .filter(|chunk| chunk.data.iter()
           .filter(|x| **x != 0)
           .collect::<Vec<_>>().len() != 0)
        .collect();
    let last_index = valid_chunks.len()-1;
    valid_chunks[last_index].data[15] = 0;
//    let mut i = last_index -1;
//    while valid_chunks[last_index].data[i] == 0 {
//        i+=1;
//    }
//    println!("{} {:x}", i, valid_chunks[last_index].data[i]);
//    let bit_pos = find_first_least_signficant_bit(valid_chunks[last_index].data[i]);
//    valid_chunks[last_index].data[i] &= ((1u64<<32)-1 - (1u64 << bit_pos as u64)) as u32;
    Ok(valid_chunks)
}

fn find_first_least_signficant_bit(mut nbr: u32) -> u8 {
    let mut condition = nbr & 1;
    let mut result = 0u8;
    while condition == 0 {
        nbr >>= 1;
        condition = nbr & 1;
        result += 1;
    }
    return result;
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct ResultSha1 {
    a:Wrapping<u32>,
    b:Wrapping<u32>,
    c:Wrapping<u32>,
    d:Wrapping<u32>,
    e:Wrapping<u32>
}

impl ResultSha1 {
    fn new(a: u32, b:u32, c:u32, d:u32, e:u32) -> ResultSha1 {
        ResultSha1{
            a: Wrapping(a),
            b: Wrapping(b),
            c: Wrapping(c),
            d: Wrapping(d),
            e: Wrapping(e)
        }
    }
}
impl AddAssign for ResultSha1 {
    fn add_assign(&mut self, rhs: Self) {
        self.a += rhs.a;
        self.b += rhs.b;
        self.c += rhs.c;
        self.d += rhs.d;
        self.e += rhs.e;
    }
}

impl Default for ResultSha1 {
    fn default() -> Self {
        ResultSha1 {
            a: Default::default(),
            b: Default::default(),
            c: Default::default(),
            d: Default::default(),
            e: Default::default()
        }
    }
}
unsafe impl OclPrm for ResultSha1 {}

fn main_operation_sha1(chunk: Chunk, mut r: ResultSha1) -> ResultSha1 {
    for i in 0..80 {
        let f : Wrapping<u32>;
        let k : Wrapping<u32>;
        if i <= 19 {
            f = (r.b & r.c)  | ((!r.b) & r.d);
            k = Wrapping(0x5A827999);
        }
        else if i <= 39{
            f = r.b ^ r.c ^ r.d;
            k = Wrapping(0x6ED9EBA1);
        }
        else if i <= 59 {
            f = (r.b & r.c) | (r.b & r.d) | (r.c & r.d);
            k = Wrapping(0x8F1BBCDC);
        }
        else {
            f = r.b ^ r.c ^ r.d;
            k = Wrapping(0xCA62C1D6);
        }

        let tmp = Wrapping(r.a.0.rotate_left(5)) + f + r.e + k + Wrapping(chunk.data[i]);
        r.e = r.d;
        r.d = r.c;
        r.c = Wrapping(r.b.0.rotate_left(30));
        r.b = r.a;
        r.a = tmp;
    }
    r
}

#[derive(Clone, Copy)]
struct Chunk {
    data: [u32; 80]
}

impl Chunk {
    // convert a vector of bytes to a vector of chunks (containing 512 bytes)
    pub fn from_bytes(data: Vec<u8>) -> Vec<Chunk>{
        assert_eq!(data.len() % 64, 0);
        let mut result = Vec::new();
        // the start of every chunk of size 512 (each chunk contains 64 bytes)
        for chunk_start_idx in (0..data.len()).step_by(64) {
            let mut chunk_data = [0; 80];
            // generate the 16 words of 32 bits
            for i in 0..16 {
                // concatenate 4 bytes
                let mut concatenated_nbr: u32 = 0;
                for j in 0..3 {
                    concatenated_nbr += data[chunk_start_idx + i * 4 + j] as u32;
                    concatenated_nbr <<= 8
                }
                concatenated_nbr += data[chunk_start_idx + i * 4 + 3] as u32;
                chunk_data[i] = concatenated_nbr;
            }
            let mut chunk = Chunk { data: chunk_data };
            chunk.extend_chunk();
            result.push(chunk);
        }
        result
    }

    fn extend_chunk(&mut self) {
        for i in 16..80 {
            self.data[i] = (self.data[i-3] ^ self.data[i-8] ^ self.data[i-14] ^ self.data[i-16])
                .rotate_left(1);
        }
    }

    pub fn generateRandomChunks(size: u32) -> Vec<Chunk>{
        let mut result = Vec::new();
        for _ in 0..size {
            let mut rc: Chunk = Chunk::default();
            for i in 0..16 {
                rc.data[i] = Self::generateRandomChunkPart()
            }
            rc.extend_chunk();
            result.push(rc);
        }
        result
    }

    fn generateRandomChunkPart() -> u32 {
        let mut tmp = 0u32;
        for i in 0..4u8 {
            let mut random_ascii: u8;
            loop {
                random_ascii = rand::random::<u8>() & 0x7f;
                if random_ascii != 0x09 &&
                    random_ascii !=  0x0d &&
                    random_ascii !=  0x0a &&
                    random_ascii !=  0x20 {
                    break;
                }
            }
            tmp |= (random_ascii as u32) << (i * 8) as u32;
        }
        tmp
    }

    fn as_u8(&self) -> [u8; 64] {
        let mut result = [0u8; 64];
        for (i, nbr) in self.data.iter().take(16).enumerate(){
            for j in 0..4{
                result[i+j] = ((nbr >> (32 - 8*(j+1))) & 0xff) as u8;
            }
        }
        result
    }
}

impl LowerHex for Chunk {
    fn fmt(&self, f: &mut Formatter<'_>) -> Result<(), Error> {
        let size  = self.data[15];
        print!("{:x}", size);
//        for i in 0..size/32{
//            print!("{:x}", self.data[i]);
//        }
//        for i in 0..size%32{
//            for j in 0..i/8{
//                print!("{:x}", (self.data[size/32] >> (32-8*(j+1))) & 0xff);
//            }
//        }
        Ok(())
    }
}

impl Debug for Chunk {
    fn fmt(&self, f: &mut Formatter<'_>) -> Result<(), Error> {
        println!("chunk");
        Ok(())
    }
}

impl PartialEq for Chunk {
    fn eq(&self, other: &Self) -> bool {
        if self.data.len() != other.data.len(){
            return false;
        }
        let mut equal = true;
        for i in 0..self.data.len() {
            if self.data[i] != other.data[i] {
                equal = false;
                break;
            }
        }
        equal
    }

}
impl Default for Chunk {
    fn default() -> Self {
        Chunk {
            data: [0; 80]
        }
    }
}

unsafe impl OclPrm for Chunk {}

// returns the 8 bits of the number in big endian
fn cut_in_bytes(mut number: u64) -> Vec<u8>{
    let mask: u64 = (1<<8) - 1;
    let mut result: Vec<u8> = Vec::with_capacity(8);
    while number != 0 {
        result.push((mask & number) as u8);
        number >>= 8;
    }
    for _ in 0..8-result.len(){
        result.push(0);
    }
    result.reverse();
    result
}
