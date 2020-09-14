// TODO create finalChunk with size 16 instead
// TODO get rid of the padding and size when solution found

typedef struct {
    char data[4];
    unsigned char size;
}Utf8Char;

typedef struct {
    unsigned int a;
    unsigned int b;
    unsigned int c;
    unsigned int d;
    unsigned int e;
}ResultSha1;

typedef struct {
    unsigned int data[80];
}Chunk;



unsigned int rotate_left(unsigned int x, char shift){
    return x << shift | x >> (32 - shift);
}

void extend_chunk(Chunk* chunk){
    char i;
    for(i=16;i<80;i++){
        chunk->data[i] = rotate_left(chunk->data[i-3] ^ chunk->data[i-8] ^ chunk->data[i-14] ^ chunk->data[i-16], 1);
    }
}

ResultSha1 main_operation_sha1(Chunk* chunk, ResultSha1 prev_res){
    unsigned char i;
    for (i=0; i<80; i++){
        unsigned int f, k;

        if (i<=19) {
            f = (prev_res.b & prev_res.c)  | ((-prev_res.b-1) & prev_res.d);
            k = 0x5A827999;
        }

        else if (i<=39){
            f = prev_res.b ^ prev_res.c ^ prev_res.d;
            k = 0x6ED9EBA1;
        }

        else if (i<=59){
            f = (prev_res.b & prev_res.c) | (prev_res.b & prev_res.d) | (prev_res.c & prev_res.d);
            k = 0x8F1BBCDC;
        }

        else {
            f = prev_res.b ^ prev_res.c ^ prev_res.d;
            k = 0xCA62C1D6;
        }

        unsigned int tmp = rotate_left(prev_res.a, 5) + f + prev_res.e + k + chunk->data[i];
        prev_res.e = prev_res.d;
        prev_res.d = prev_res.c;
        prev_res.c = rotate_left(prev_res.b, 30);
        prev_res.b = prev_res.a;
        prev_res.a = tmp;
    }
    return prev_res;
}

ResultSha1 addResSha1(ResultSha1* x, ResultSha1* y){
    ResultSha1 result;
    result.a = x->a + y->a;
    result.b = x->b + y->b;
    result.c = x->c + y->c;
    result.d = x->d + y->d;
    result.e = x->e + y->e;
    return result;
}



unsigned int get_probability_bits(ResultSha1* r, unsigned char difficulty, unsigned char probability_len){
    //  we assume probability_len is picked accordingly to difficulty, so that difficulty + probability_len <= 32
    unsigned int mask = (1 << probability_len) -1;
    int difference_first_byte = 32 - difficulty;
    // if it's less than 32 bits long
    if (difference_first_byte > 0){
        if (difficulty + probability_len <= 32) {
            unsigned char shift = difference_first_byte - probability_len;
            return (r->a >> shift) & mask;
        }
        else {
            unsigned int result;
            // we want to retrieve the part of probability_len that sit on r.a, and then move it to the upper part of the result
            result = (((1 << difference_first_byte) -1) & r->a) << (probability_len - difference_first_byte);
            // we want to retrieve the part of probability_len that sit on r.b, and then move it to the lower part of the result
            result |=  r->b & ((1 << (probability_len - difference_first_byte)) -1);
            return result;
        }
    }
    // it's more than 32 bits long
    else {
         unsigned char shift = 64 - difficulty - probability_len;
         return (r->b >> shift) & mask;
    }
}

void prepare_final_chunk(Chunk* c, unsigned char padding_position, unsigned long int total_size){

    c->data[padding_position] = 0x80000000;
    // the size is encoded on 64 bits
    c->data[14] = total_size >> 32;
    c->data[15] = total_size & 0xffffffff;
    extend_chunk(c);
}


// fills the chunk with 9 ascii characters, and returns how many integers have been filled in the chunk
// or -1 if we generate a [\t\r\n ] character
char fill_chunk(Chunk* c, unsigned long nbr){
    unsigned char idx = 0;
    unsigned char i;
    unsigned char ascii_char;
    while (nbr){
        for(i=0; i<4; i++){
            ascii_char =  (nbr & 0x7f);
            if (ascii_char == 0x09 || ascii_char == 0x0a || ascii_char == 0x0d || ascii_char == 0x20){
                return -1;
            }
            c->data[idx] |= ascii_char << (i*8);
            nbr >>= 7;
        }
        idx += 1;
    }
    extend_chunk(c);
    return idx;
}

unsigned char is_final_answer(ResultSha1* r, unsigned long final_result_mask){

    return (r->a & 0xffffffff) == 0 && (r->b & 0xf0000000) == 0;
    if (final_result_mask <= (1ul << 32) -1){
        return (r->a & final_result_mask) == 0;
    }
    else{
        return (r->a & (final_result_mask >> 32)) == 0 &&
            (r->b & (final_result_mask & 0xffffffff)) == 0;
    }
}

// return the result from the chunk
ResultSha1 get_next_r(Chunk* chunk, ResultSha1* previous_r){
    ResultSha1 r = main_operation_sha1(chunk, *previous_r);
    return addResSha1(previous_r, &r);
}

__kernel void explore_sha1(unsigned char difficulty,
    __global Chunk* random_chunks,
    ResultSha1 r_initial,
    unsigned int bit_len,
    __global unsigned char* finished,
    __global Chunk* result,
    unsigned char proba_len) {

    difficulty *= 4;
//    printf("difficulty %d", difficulty);
    unsigned long final_result_mask = ((1ul << difficulty) - 1) << (64 - difficulty);

    Chunk message_chunks[3];
    // systematically add the random chunk
    message_chunks[0] = random_chunks[get_global_id(0)];

    bit_len += 512;

    unsigned char message_chunks_idx = 1;

    // add an initial random chunk's hash to have a different starting point per work-item
    // we don't need to extend the chunk, it's already extended
    ResultSha1 tmp_r = main_operation_sha1(message_chunks, r_initial);
    ResultSha1 r = addResSha1(&tmp_r, &r_initial);

    unsigned long index = 0;
    Chunk most_probable_chunk_minimize, most_probable_chunk_maximize;
    ResultSha1 r_minimize_carry, r_maximize_carry;
    unsigned char min_found=0, max_found=0;
    unsigned int probability_bits;

    // we have 1/2^(proba_len) to find the max or min probability, so the probability not to find them after n tries is (1-1/2^(proba_len*2))^n
    // if we set proba_len = 4, we have 99.4% of chance to find them in 80 tries
    while ((!min_found || !max_found) && index < (1ul<<63)) {
        if (!*finished){
            Chunk c = {0};
            // skip forbidden values
            if (fill_chunk(&c, index) == -1){
                index += 1;
                continue;
            }
            tmp_r = get_next_r(&c, &r);

            probability_bits = get_probability_bits(&tmp_r, difficulty, proba_len);
            if (!max_found && probability_bits == ((1 << proba_len) -1)){
                max_found = 1;
                r_maximize_carry = tmp_r;
                most_probable_chunk_maximize = c;
            }
            else if (!min_found && probability_bits == 0){
                min_found = 1;
                r_minimize_carry = tmp_r;
                most_probable_chunk_minimize = c;
            }
        }
        else {
            return;
        }
        index += 1;
    }
    // we certainly found the most probable chunks we could

    // let's pretend we added the chunk (we'll add one of the two later)
    bit_len += 512;

    char padding_idx;
    index = 0;
    // we can fill up to 55 ascii characters, 9 will be enough for difficulties that are under 32-proba_len (2⁶³ possibilities)
    while (index < (1ul<<63) && !*finished){
//    while (index < (1ul<<9) && !*finished){
        Chunk c = {0};
        padding_idx = fill_chunk(&c, index);
        // skip forbidden characters
        if (padding_idx == -1){
            index += 1;
            continue;
        }
        prepare_final_chunk(&c, padding_idx, bit_len + padding_idx * 32);

        // try with the result that minimizes overflowing
        tmp_r = get_next_r(&c, &r_minimize_carry);
        if (is_final_answer(&tmp_r, final_result_mask)){
            // bingo!!
            // fill the buffer with the chunk and stop everything
            if (!*finished){
                // notify other work-items that somebody has found the solution
                *finished = 1;
                unsigned char k;
                message_chunks[message_chunks_idx] = most_probable_chunk_minimize;
                message_chunks_idx += 1;
                message_chunks[message_chunks_idx] = c;
                message_chunks_idx += 1;
                for(k=0; k<message_chunks_idx; k++){
                    result[k] = message_chunks[k];
                }
                return;
            }
        }
        // try with the result that maximizes overflowing
        tmp_r = get_next_r(&c, &r_maximize_carry);

        if (is_final_answer(&tmp_r, final_result_mask)){
            // bingo!!
            // fill the buffer with the chunk and stop everything
            if (!*finished){
                // notify other work-items that somebody has found the solution
                *finished = 1;
//                printf("found with carry %08x", tmp_r.a);
                unsigned char k;
                message_chunks[message_chunks_idx] = most_probable_chunk_maximize;
                message_chunks_idx += 1;
                message_chunks[message_chunks_idx] = c;
                message_chunks_idx += 1;
                for(k=0; k<message_chunks_idx; k++){
                    result[k] = message_chunks[k];
                }
                return;
            }
        }
        index += 1;
    }
}


