#!/usr/bin/env ruby

$VERBOSE = true

require 'rubyunit'
require 'ftools'
require 'zip'

include Zip

class AbstractInputStreamTest < RUNIT::TestCase
  # AbstractInputStream subclass that provides a read method
  
  TEST_LINES = [ "Hello world#{$/}", 
    "this is the second line#{$/}", 
    "this is the last line"]
  TEST_STRING = TEST_LINES.join
  class TestAbstractInputStream 
    include AbstractInputStream
    def initialize(aString)
      @contents = aString
      @readPointer = 0
    end

    def read(charsToRead)
      retVal=@contents[@readPointer, charsToRead]
      @readPointer+=charsToRead
      return retVal
    end

    def produceInput
      read(100)
    end

    def inputFinished?
      @contents[@readPointer] == nil
    end
  end

  def setup
    @io = TestAbstractInputStream.new(TEST_STRING)
  end
  
  def test_gets
    assert_equals(TEST_LINES[0], @io.gets)
    assert_equals(TEST_LINES[1], @io.gets)
    assert_equals(TEST_LINES[2], @io.gets)
    assert_equals(nil, @io.gets)
  end

  def test_getsMultiCharSeperator
    assert_equals("Hell", @io.gets("ll"))
    assert_equals("o world#{$/}this is the second l", @io.gets("d l"))
  end

  def test_each_line
    lineNumber=0
    @io.each_line {
      |line|
      assert_equals(TEST_LINES[lineNumber], line)
      lineNumber+=1
    }
  end

  def test_readlines
    assert_equals(TEST_LINES, @io.readlines)
  end

  def test_readline
    test_gets
    begin
      @io.readline
      fail "EOFError expected"
      rescue EOFError
    end
  end
end

class ZipEntryTest < RUNIT::TestCase
  TEST_ZIPFILE = "someZipFile.zip"
  TEST_COMMENT = "a comment"
  TEST_COMPRESSED_SIZE = 1234
  TEST_CRC = 325324
  TEST_EXTRA = "Some data here"
  TEST_COMPRESSIONMETHOD = ZipEntry::DEFLATED
  TEST_NAME = "entry name"
  TEST_SIZE = 8432
  TEST_ISDIRECTORY = false

  def test_constructorAndGetters
    entry = ZipEntry.new(TEST_ZIPFILE,
			 TEST_NAME,
			 TEST_COMMENT,
			 TEST_EXTRA,
			 TEST_COMPRESSED_SIZE,
			 TEST_CRC,
			 TEST_COMPRESSIONMETHOD,
			 TEST_SIZE)

    assert_equals(TEST_COMMENT, entry.comment)
    assert_equals(TEST_COMPRESSED_SIZE, entry.compressedSize)
    assert_equals(TEST_CRC, entry.crc)
    assert_equals(TEST_EXTRA, entry.extra)
    assert_equals(TEST_COMPRESSIONMETHOD, entry.compressionMethod)
    assert_equals(TEST_NAME, entry.name)
    assert_equals(TEST_SIZE, entry.size)
    assert_equals(TEST_ISDIRECTORY, entry.isDirectory)
  end

  def test_equality
    entry1 = ZipEntry.new("file.zip", "name",  "isNotCompared", 
			  "something extra", 123, 1234, 
			  ZipEntry::DEFLATED, 10000)  
    entry2 = ZipEntry.new("file.zip", "name",  "isNotComparedXXX", 
			  "something extra", 123, 1234, 
			  ZipEntry::DEFLATED, 10000)  
    entry3 = ZipEntry.new("file.zip", "name2", "isNotComparedXXX", 
			  "something extra", 123, 1234, 
			  ZipEntry::DEFLATED, 10000)  
    entry4 = ZipEntry.new("file.zip", "name2", "isNotComparedXXX", 
			  "something extraXX", 123, 1234, 
			  ZipEntry::DEFLATED, 10000)  
    entry5 = ZipEntry.new("file.zip", "name2", "isNotComparedXXX", 
			  "something extraXX", 12,  1234, 
			  ZipEntry::DEFLATED, 10000)  
    entry6 = ZipEntry.new("file.zip", "name2", "isNotComparedXXX", 
			  "something extraXX", 12,  123, 
			  ZipEntry::DEFLATED, 10000)  
    entry7 = ZipEntry.new("file.zip", "name2", "isNotComparedXXX", 
			  "something extraXX", 12,  123,  
			  ZipEntry::STORED,   10000)  
    entry8 = ZipEntry.new("file.zip", "name2", "isNotComparedXXX", 
			  "something extraXX", 12,  123,  
			  ZipEntry::STORED,   100000)  

    assert_equals(entry1, entry1)
    assert_equals(entry1, entry2)

    assert(entry2 != entry3)
    assert(entry3 != entry4)
    assert(entry4 != entry5)
    assert(entry5 != entry6)
    assert(entry6 != entry7)
    assert(entry7 != entry8)

    assert(entry7 != "hello")
    assert(entry7 != 12)
  end
end

module IOizeString
  attr_reader :tell
  
  def read(count = nil)
    @tell ||= 0
    count = size unless count
    retVal = slice(@tell, count)
    @tell += count
    return retVal
  end

  def seek(index, offset)
    @tell ||= 0
    case offset
    when IO::SEEK_END
      newPos = size + index
    when IO::SEEK_SET
      newPos = index
    when IO::SEEK_CUR
      newPos = @tell + index
    else
      raise "Error in test method IOizeString::seek"
    end
    if (newPos < 0 || newPos >= size)
      raise Errno::EINVAL
    else
      @tell=newPos
    end
  end

  def reset
    @tell = 0
  end
end

class ZipLocalEntryTest < RUNIT::TestCase
  def test_readLocalEntryHeaderOfFirstTestZipEntry
    File.open(TestZipFile::TEST_ZIP3.zipName) {
      |file|
      entry = ZipEntry.readLocalEntry(file)
      
      assert_equal("", entry.comment)
      # Differs from windows and unix because of CR LF
      # assert_equal(480, entry.compressedSize)
      # assert_equal(0x2a27930f, entry.crc)
      # extra field is 21 bytes long
      # probably contains some unix attrutes or something
      # disabled: assert_equal(nil, entry.extra)
      assert_equal(ZipEntry::DEFLATED, entry.compressionMethod)
      assert_equal(TestZipFile::TEST_ZIP3.entryNames[0], entry.name)
      assert_equal(File.size(TestZipFile::TEST_ZIP3.entryNames[0]), entry.size)
      assert(! entry.isDirectory)
    }
  end

  def test_readLocalEntryFromNonZipFile
    File.open("ziptest.rb") {
      |file|
      assert_equals(nil, ZipEntry.readLocalEntry(file))
    }
  end

  def test_readLocalEntryFromTruncatedZipFile
    zipFragment=""
    File.open(TestZipFile::TEST_ZIP2.zipName) { |f| zipFragment = f.read(12) } # local header is at least 30 bytes
    zipFragment.extend(IOizeString).reset
    entry = ZipEntry.new
    entry.readLocalEntry(zipFragment)
    fail "ZipError expected"
  rescue ZipError
  end

  def test_writeEntry
    entry = ZipEntry.new("file.zip", "entryName", "my little comment", 
			 "thisIsSomeExtraInformation", 100, 987654, 
			 ZipEntry::DEFLATED, 400)
    writeToFile("localEntryHeader.bin", "centralEntryHeader.bin",  entry)
    entryReadLocal, entryReadCentral = readFromFile("localEntryHeader.bin", "centralEntryHeader.bin")
    compareLocalEntryHeaders(entry, entryReadLocal)
    compareCDirEntryHeaders(entry, entryReadCentral)
  end
  
  private
  def compareLocalEntryHeaders(entry1, entry2)
    assert_equals(entry1.compressedSize   , entry2.compressedSize)
    assert_equals(entry1.crc              , entry2.crc)
    assert_equals(entry1.extra            , entry2.extra)
    assert_equals(entry1.compressionMethod, entry2.compressionMethod)
    assert_equals(entry1.name             , entry2.name)
    assert_equals(entry1.size             , entry2.size)
    assert_equals(entry1.localHeaderOffset, entry2.localHeaderOffset)
  end

  def compareCDirEntryHeaders(entry1, entry2)
    compareLocalEntryHeaders(entry1, entry2)
    assert_equals(entry1.comment, entry2.comment)
  end

  def writeToFile(localFileName, centralFileName, entry)
    File.open(localFileName,   "wb") { |f| entry.writeLocalEntry(f) }
    File.open(centralFileName, "wb") { |f| entry.writeCDirEntry(f)  }
  end

  def readFromFile(localFileName, centralFileName)
    localEntry = nil
    cdirEntry  = nil
    File.open(localFileName,   "rb") { |f| localEntry = ZipEntry.readLocalEntry(f) }
    File.open(centralFileName, "rb") { |f| cdirEntry  = ZipEntry.readCDirEntry(f) }
    return [localEntry, cdirEntry]
  end
end


module DecompressorTests
  # expects @refText and @decompressor

  def test_readEverything
    assert_equals(@refText, @decompressor.read)
  end
    
  def test_readInChunks
    chunkSize = 5
    while (decompressedChunk = @decompressor.read(chunkSize))
      assert_equals(@refText.slice!(0, chunkSize), decompressedChunk)
    end
    assert_equals(0, @refText.size)
  end
end

class InflaterTest < RUNIT::TestCase
  include DecompressorTests

  def setup
    @file = File.new("file1.txt.deflatedData", "rb")
    @refText=""
    File.open("file1.txt") { |f| @refText = f.read }
    @decompressor = Inflater.new(@file)
  end

  def teardown
    @file.close
  end
end


class PassThruDecompressorTest < RUNIT::TestCase
  include DecompressorTests
  TEST_FILE="file1.txt"
  def setup
    @file = File.new(TEST_FILE)
    @refText=""
    File.open(TEST_FILE) { |f| @refText = f.read }
    @decompressor = PassThruDecompressor.new(@file, File.size(TEST_FILE))
  end

  def teardown
    @file.close
  end
end

 
module AssertEntry
  def assertNextEntry(filename, zis)
    assertEntry(filename, zis, zis.getNextEntry.name)
  end

  def assertEntry(filename, zis, entryName)
    assert_equals(filename, entryName)
    assertEntryContentsForStream(filename, zis, entryName)
  end

  def assertEntryContentsForStream(filename, zis, entryName)
    File.open(filename, "rb") {
      |file|
      expected = file.read
      actual   = zis.read
      if (expected != actual)
	if (expected.length > 400 || actual.length > 400)
	  zipEntryFilename=entryName+".zipEntry"
	  File.open(zipEntryFilename, "wb") { |file| file << actual }
	  fail("File '#{filename}' is different from '#{zipEntryFilename}'")
	else
	  assert_equals(expected, actual)
	end
      end
    }
  end

  def AssertEntry.assertContents(filename, aString)
    fileContents = ""
    File.open(filename, "rb") { |f| fileContents = f.read }
    if (fileContents != aString)
      if (expected.length > 400 || actual.length > 400)
	stringFile = filename + ".other"
	File.open(stringFile, "wb") { |f| f << aString }
	fail("File '#{filename}' is different from contents of string stored in '#{stringFile}'")
      else
	assert_equals(expected, actual)
      end
    end
  end

  def assertStreamContents(zis, testZipFile)
    assert(zis != nil)
    testZipFile.entryNames.each {
      |entryName|
      assertNextEntry(entryName, zis)
    }
    assert_equals(nil, zis.getNextEntry)
  end

  def assertTestZipContents(testZipFile)
    ZipInputStream.open(testZipFile.zipName) {
      |zis|
      assertStreamContents(zis, testZipFile)
    }
  end

  def assertEntryContents(zipFile, entryName, filename = entryName.to_s)
    zis = zipFile.getInputStream(entryName)
    assertEntryContentsForStream(filename, zis, entryName)
  ensure 
    zis.close if zis
  end
end



class ZipInputStreamTest < RUNIT::TestCase
  include AssertEntry

  def test_new
    zis = ZipInputStream.new(TestZipFile::TEST_ZIP2.zipName)
    assertStreamContents(zis, TestZipFile::TEST_ZIP2)
    zis.close    
  end

  def test_openWithBlock
    ZipInputStream.open(TestZipFile::TEST_ZIP2.zipName) {
      |zis|
      assertStreamContents(zis, TestZipFile::TEST_ZIP2)
    }
  end

  def test_openWithoutBlock
    zis = ZipInputStream.open(TestZipFile::TEST_ZIP2.zipName)
    assertStreamContents(zis, TestZipFile::TEST_ZIP2)
  end

  def test_incompleteReads
    ZipInputStream.open(TestZipFile::TEST_ZIP2.zipName) {
      |zis|
      entry = zis.getNextEntry
      assert_equals(TestZipFile::TEST_ZIP2.entryNames[0], entry.name)
      assert zis.gets.length > 0
      entry = zis.getNextEntry
      assert_equals(TestZipFile::TEST_ZIP2.entryNames[1], entry.name)
      assert_equals(0, entry.size)
      assert_equals(nil, zis.gets)
      entry = zis.getNextEntry
      assert_equals(TestZipFile::TEST_ZIP2.entryNames[2], entry.name)
      assert zis.gets.length > 0
      entry = zis.getNextEntry
      assert_equals(TestZipFile::TEST_ZIP2.entryNames[3], entry.name)
      assert zis.gets.length > 0
    }
  end
  
end

class TestFiles
  RANDOM_ASCII_FILE1  = "randomAscii1.txt"
  RANDOM_ASCII_FILE2  = "randomAscii2.txt"
  RANDOM_ASCII_FILE3  = "randomAscii3.txt"
  RANDOM_BINARY_FILE1 = "randomBinary1.bin"
  RANDOM_BINARY_FILE2 = "randomBinary2.bin"

  EMPTY_TEST_DIR      = "emptytestdir"

  ASCII_TEST_FILES  = [ RANDOM_ASCII_FILE1, RANDOM_ASCII_FILE2, RANDOM_ASCII_FILE3 ] 
  BINARY_TEST_FILES = [ RANDOM_BINARY_FILE1, RANDOM_BINARY_FILE2 ]
  TEST_DIRECTORIES  = [ EMPTY_TEST_DIR ]
  TEST_FILES        = [ ASCII_TEST_FILES, BINARY_TEST_FILES, EMPTY_TEST_DIR ].flatten!

  def TestFiles.createTestFiles(recreate)
    if (recreate || 
	! (TEST_FILES.inject(true) { |accum, element| accum && File.exists?(element) }))
      
      ASCII_TEST_FILES.each_with_index { 
	|filename, index| 
	createRandomAscii(filename, 1E4 * (index+1))
      }
      
      BINARY_TEST_FILES.each_with_index { 
	|filename, index| 
	createRandomBinary(filename, 1E4 * (index+1))
      }

      ensureDir(EMPTY_TEST_DIR)
    end
  end

  private
  def TestFiles.createRandomAscii(filename, size)
    File.open(filename, "wb") {
      |file|
      while (file.tell < size)
	file << rand
      end
    }
  end

  def TestFiles.createRandomBinary(filename, size)
    File.open(filename, "wb") {
      |file|
      while (file.tell < size)
	file << rand.to_a.pack("V")
      end
    }
  end

  def TestFiles.ensureDir(name) 
    if File.exists?(name)
      return if File.stat(name).directory?
      File.delete(name)
    end
    Dir.mkdir(name)
  end

end

# For representation and creation of
# test data
class TestZipFile
  attr_accessor :zipName, :entryNames, :comment

  def initialize(zipName, entryNames, comment = "")
    @zipName=zipName
    @entryNames=entryNames
    @comment = comment
  end

  def TestZipFile.createTestZips(recreate)
    files = Dir.entries(".")
    if (recreate || 
	    ! (files.index(TEST_ZIP1.zipName) &&
	       files.index(TEST_ZIP2.zipName) &&
	       files.index(TEST_ZIP3.zipName) &&
	       files.index("empty.txt")      &&
	       files.index("short.txt")      &&
	       files.index("longAscii.txt")  &&
	       files.index("longBinary.bin") ))
      raise "failed to create test zip '#{TEST_ZIP1.zipName}'" unless 
	system("zip #{TEST_ZIP1.zipName} ziptest.rb")
      raise "failed to remove entry from '#{TEST_ZIP1.zipName}'" unless 
	system("zip #{TEST_ZIP1.zipName} -d ziptest.rb")
      
      File.open("empty.txt", "w") {}
      
      File.open("short.txt", "w") { |file| file << "ABCDEF" }
      ziptestTxt=""
      File.open("ziptest.rb") { |file| ziptestTxt=file.read }
      File.open("longAscii.txt", "w") {
	|file|
	while (file.tell < 1E5)
	  file << ziptestTxt
	end
      }
      
      testBinaryPattern=""
      File.open("empty.zip") { |file| testBinaryPattern=file.read }
      testBinaryPattern *= 4
      
      File.open("longBinary.bin", "wb") {
	|file|
	while (file.tell < 3E5)
	  file << testBinaryPattern << rand
	end
      }
      raise "failed to create test zip '#{TEST_ZIP2.zipName}'" unless 
	system("zip #{TEST_ZIP2.zipName} #{TEST_ZIP2.entryNames.join(' ')}")
      raise "failed to add comment to test zip '#{TEST_ZIP2.zipName}'" unless 
	system("echo '#{TEST_ZIP2.comment}' | zip -z #{TEST_ZIP2.zipName}")

      raise "failed to create test zip '#{TEST_ZIP3.zipName}'" unless 
	system("zip #{TEST_ZIP3.zipName} #{TEST_ZIP3.entryNames.join(' ')}")
    end
  rescue 
    raise $!.to_s + 
      "\n\nziptest.rb requires the Info-ZIP program 'zip' in the path\n" +
      "to create test data. If you don't have it you can download\n"   +
      "the necessary test files at http://sf.net/projects/rubyzip."
  end

  TEST_ZIP1 = TestZipFile.new("empty.zip", [])
  TEST_ZIP2 = TestZipFile.new("4entry.zip", %w{ longAscii.txt empty.txt short.txt longBinary.bin}, 
			      "my zip comment")
  TEST_ZIP3 = TestZipFile.new("test1.zip", %w{ file1.txt })
end


class AbstractOutputStreamTest < RUNIT::TestCase
  class TestOutputStream
    include AbstractOutputStream

    attr_accessor :buffer

    def initialize
      @buffer = ""
    end

    def << (data)
      @buffer << data
      self
    end
  end

  def setup
    @outputStream = TestOutputStream.new

    @origCommaSep = $,
    @origOutputSep = $\
  end

  def teardown
    $, = @origCommaSep
    $\ = @origOutputSep
  end

  def test_write
    count = @outputStream.write("a little string")
    assert_equals("a little string", @outputStream.buffer)
    assert_equals("a little string".length, count)

    count = @outputStream.write(". a little more")
    assert_equals("a little string. a little more", @outputStream.buffer)
    assert_equals(". a little more".length, count)
  end
  
  def test_print
    $\ = nil # record separator set to nil
    @outputStream.print("hello")
    assert_equals("hello", @outputStream.buffer)

    @outputStream.print(" world.")
    assert_equals("hello world.", @outputStream.buffer)
    
    @outputStream.print(" You ok ",  "out ", "there?")
    assert_equals("hello world. You ok out there?", @outputStream.buffer)

    $\ = "\n"
    @outputStream.print
    assert_equals("hello world. You ok out there?\n", @outputStream.buffer)

    @outputStream.print("I sure hope so!")
    assert_equals("hello world. You ok out there?\nI sure hope so!\n", @outputStream.buffer)

    $, = "X"
    @outputStream.buffer = ""
    @outputStream.print("monkey", "duck", "zebra")
    assert_equals("monkeyXduckXzebra\n", @outputStream.buffer)

    $\ = nil
    @outputStream.buffer = ""
    @outputStream.print(20)
    assert_equals("20", @outputStream.buffer)
  end
  
  def test_printf
    @outputStream.printf("%d %04x", 123, 123) 
    assert_equals("123 007b", @outputStream.buffer)
  end
  
  def test_putc
    @outputStream.putc("A")
    assert_equals("A", @outputStream.buffer)
    @outputStream.putc(65)
    assert_equals("AA", @outputStream.buffer)
  end

  def test_puts
    @outputStream.puts
    assert_equals("\n", @outputStream.buffer)

    @outputStream.puts("hello", "world")
    assert_equals("\nhello\nworld\n", @outputStream.buffer)

    @outputStream.buffer = ""
    @outputStream.puts("hello\n", "world\n")
    assert_equals("hello\nworld\n", @outputStream.buffer)
    
    @outputStream.buffer = ""
    @outputStream.puts(["hello\n", "world\n"])
    assert_equals("hello\nworld\n", @outputStream.buffer)

    @outputStream.buffer = ""
    @outputStream.puts(["hello\n", "world\n"], "bingo")
    assert_equals("hello\nworld\nbingo\n", @outputStream.buffer)

    @outputStream.buffer = ""
    @outputStream.puts(16, 20, 50, "hello")
    assert_equals("16\n20\n50\nhello\n", @outputStream.buffer)
  end
end


module CrcTest
  def runCrcTest(compressorClass)
    str = "Here's a nice little text to compute the crc for! Ho hum, it is nice nice nice nice indeed."
    fakeOut = AbstractOutputStreamTest::TestOutputStream.new
    
    deflater = compressorClass.new(fakeOut)
    deflater << str
    assert_equals(0x919920fc, deflater.crc)
  end
end



class PassThruCompressorTest < RUNIT::TestCase
  include CrcTest

  def test_size
    File.open("dummy.txt", "wb") {
      |file|
      compressor = PassThruCompressor.new(file)
      
      assert_equals(0, compressor.size)
      
      t1 = "hello world"
      t2 = ""
      t3 = "bingo"
      
      compressor << t1
      assert_equals(compressor.size, t1.size)
      
      compressor << t2
      assert_equals(compressor.size, t1.size + t2.size)
      
      compressor << t3
      assert_equals(compressor.size, t1.size + t2.size + t3.size)
    }
  end

  def test_crc
    runCrcTest(PassThruCompressor)
  end
end

class DeflaterTest < RUNIT::TestCase
  include CrcTest

  def test_outputOperator
    txt = loadFile("ziptest.rb")
    deflate(txt, "deflatertest.bin")
    inflatedTxt = inflate("deflatertest.bin")
    assert_equals(txt, inflatedTxt)
  end

  private
  def loadFile(fileName)
    txt = nil
    File.open(fileName, "rb") { |f| txt = f.read }
  end

  def deflate(data, fileName)
    File.open(fileName, "wb") {
      |file|
      deflater = Deflater.new(file)
      deflater << data
      deflater.finish
      assert_equals(deflater.size, data.size)
      file << "trailing data for zlib with -MAX_WBITS"
    }
  end

  def inflate(fileName)
    txt = nil
    File.open(fileName, "rb") {
      |file|
      inflater = Inflater.new(file)
      txt = inflater.read
    }
  end

  def test_crc
    runCrcTest(Deflater)
  end
end

class ZipOutputStreamTest < RUNIT::TestCase
  include AssertEntry

  TEST_ZIP = TestZipFile::TEST_ZIP2.clone
  TEST_ZIP.zipName = "output.zip"

  def test_new
    zos = ZipOutputStream.new(TEST_ZIP.zipName)
    zos.comment = TEST_ZIP.comment
    writeTestZip(zos)
    zos.close
    assertTestZipContents(TEST_ZIP)
  end

  def test_open
    ZipOutputStream.open(TEST_ZIP.zipName) {
      |zos|
      zos.comment = TEST_ZIP.comment
      writeTestZip(zos)
    }
    assertTestZipContents(TEST_ZIP)
  end

  def test_writingToClosedStream
    assertIOErrorInClosedStream { |zos| zos << "hello world" }
    assertIOErrorInClosedStream { |zos| zos.puts "hello world" }
    assertIOErrorInClosedStream { |zos| zos.write "hello world" }
  end

  def test_cannotOpenFile
    name = TestFiles::EMPTY_TEST_DIR
    begin
      zos = ZipOutputStream.open(name)
    rescue Exception
      assert($!.kind_of?(Errno::EISDIR) || $!.kind_of?(Errno::EEXIST),
	      "Expected Errno::EISDIR (or on win/cygwin: Errno::EEXIST), but was: #{$!}")
    end
  end

  def assertIOErrorInClosedStream
    assert_exception(IOError) {
      zos = ZipOutputStream.new("test_putOnClosedStream.zip")
      zos.close
      yield zos
    }
  end

  def writeTestZip(zos)
    TEST_ZIP.entryNames.each {
      |entryName|
      zos.putNextEntry(entryName)
      File.open(entryName, "rb") { |f| zos.write(f.read) }
    }
  end
end



module Enumerable
  def compareEnumerables(otherEnumerable)
    otherAsArray = otherEnumerable.to_a
    index=0
    each_with_index {
      |element, index|
      return false unless yield(element, otherAsArray[index])
    }
    return index+1 == otherAsArray.size
  end
end


class ZipCentralDirectoryEntryTest < RUNIT::TestCase

  def test_readFromStream
    File.open("testDirectory.bin", "rb") {
      |file|
      entry = ZipEntry.readCDirEntry(file)
      
      assert_equals("longAscii.txt", entry.name)
      assert_equals(ZipEntry::DEFLATED, entry.compressionMethod)
      assert_equals(106490, entry.size)
      assert_equals(3784, entry.compressedSize)
      assert_equals(0xfcd1799c, entry.crc)
      assert_equals("", entry.comment)

      entry = ZipEntry.readCDirEntry(file)
      assert_equals("empty.txt", entry.name)
      assert_equals(ZipEntry::STORED, entry.compressionMethod)
      assert_equals(0, entry.size)
      assert_equals(0, entry.compressedSize)
      assert_equals(0x0, entry.crc)
      assert_equals("", entry.comment)

      entry = ZipEntry.readCDirEntry(file)
      assert_equals("short.txt", entry.name)
      assert_equals(ZipEntry::STORED, entry.compressionMethod)
      assert_equals(6, entry.size)
      assert_equals(6, entry.compressedSize)
      assert_equals(0xbb76fe69, entry.crc)
      assert_equals("", entry.comment)

      entry = ZipEntry.readCDirEntry(file)
      assert_equals("longBinary.bin", entry.name)
      assert_equals(ZipEntry::DEFLATED, entry.compressionMethod)
      assert_equals(1000024, entry.size)
      assert_equals(70847, entry.compressedSize)
      assert_equals(0x10da7d59, entry.crc)
      assert_equals("", entry.comment)

      entry = ZipEntry.readCDirEntry(file)
      assert_equals(nil, entry)
# Fields that are not check by this test:
#          version made by                 2 bytes
#          version needed to extract       2 bytes
#          general purpose bit flag        2 bytes
#          last mod file time              2 bytes
#          last mod file date              2 bytes
#          compressed size                 4 bytes
#          uncompressed size               4 bytes
#          disk number start               2 bytes
#          internal file attributes        2 bytes
#          external file attributes        4 bytes
#          relative offset of local header 4 bytes

#          file name (variable size)
#          extra field (variable size)
#          file comment (variable size)

    }
  end

  def test_ReadEntryFromTruncatedZipFile
    fragment=""
    File.open("testDirectory.bin") { |f| fragment = f.read(12) } # cdir entry header is at least 46 bytes
    fragment.extend(IOizeString)
    entry = ZipEntry.new
    entry.readCDirEntry(fragment)
    fail "ZipError expected"
  rescue ZipError
  end

end

class ZipCentralDirectoryTest < RUNIT::TestCase

  def test_readFromStream
    File.open(TestZipFile::TEST_ZIP2.zipName, "rb") {
      |zipFile|
      cdir = ZipCentralDirectory.readFromStream(zipFile)

      assert_equals(TestZipFile::TEST_ZIP2.entryNames.size, cdir.size)
      assert(cdir.compareEnumerables(TestZipFile::TEST_ZIP2.entryNames) { 
		      |cdirEntry, testEntryName|
		      cdirEntry.name == testEntryName
		    })
      assert_equals(TestZipFile::TEST_ZIP2.comment, cdir.comment)
    }
  end

  def test_readFromInvalidStream
    File.open("ziptest.rb", "rb") {
      |zipFile|
      cdir = ZipCentralDirectory.new
      cdir.readFromStream(zipFile)
    }
    fail "ZipError expected!"
  rescue ZipError
  end

  def test_ReadFromTruncatedZipFile
    fragment=""
    File.open("testDirectory.bin") { |f| fragment = f.read }
    fragment.slice!(12) # removed part of first cdir entry. eocd structure still complete
    fragment.extend(IOizeString)
    entry = ZipCentralDirectory.new
    entry.readFromStream(fragment)
    fail "ZipError expected"
  rescue ZipError
  end

  def test_writeToStream
    entries = [ ZipEntry.new("file.zip", "flimse", "myComment", "somethingExtra"),
      ZipEntry.new("file.zip", "secondEntryName"),
      ZipEntry.new("file.zip", "lastEntry.txt", "Has a comment too") ]
    cdir = ZipCentralDirectory.new(entries, "my zip comment")
    File.open("cdirtest.bin", "wb") { |f| cdir.writeToStream(f) }
    cdirReadback = ZipCentralDirectory.new
    File.open("cdirtest.bin", "rb") { |f| cdirReadback.readFromStream(f) }
    
    assert_equals(cdir.entries, cdirReadback.entries)
  end

  def test_equality
    cdir1 = ZipCentralDirectory.new([ ZipEntry.new("file.zip", "flimse", nil, 
						   "somethingExtra"),
				     ZipEntry.new("file.zip", "secondEntryName"),
				     ZipEntry.new("file.zip", "lastEntry.txt") ], 
				   "my zip comment")
    cdir2 = ZipCentralDirectory.new([ ZipEntry.new("file.zip", "flimse", nil, 
						   "somethingExtra"),
				     ZipEntry.new("file.zip", "secondEntryName"),
				     ZipEntry.new("file.zip", "lastEntry.txt") ], 
				   "my zip comment")
    cdir3 = ZipCentralDirectory.new([ ZipEntry.new("file.zip", "flimse", nil, 
						   "somethingExtra"),
				     ZipEntry.new("file.zip", "secondEntryName"),
				     ZipEntry.new("file.zip", "lastEntry.txt") ], 
				   "comment?")
    cdir4 = ZipCentralDirectory.new([ ZipEntry.new("file.zip", "flimse", nil, 
						   "somethingExtra"),
				     ZipEntry.new("file.zip", "lastEntry.txt") ], 
				   "comment?")
    assert_equals(cdir1, cdir1)
    assert_equals(cdir1, cdir2)

    assert(cdir1 !=  cdir3)
    assert(cdir2 !=  cdir3)
    assert(cdir2 !=  cdir3)
    assert(cdir3 !=  cdir4)

    assert(cdir3 !=  "hello")
  end
end


class BasicZipFileTest < RUNIT::TestCase
  include AssertEntry

  def setup
    @zipFile = ZipFile.new(TestZipFile::TEST_ZIP2.zipName)
    @testEntryNameIndex=0
  end

  def nextTestEntryName
    retVal=TestZipFile::TEST_ZIP2.entryNames[@testEntryNameIndex]
    @testEntryNameIndex+=1
    return retVal
  end
    
  def test_entries
    assert_equals(TestZipFile::TEST_ZIP2.entryNames, @zipFile.entries.map {|e| e.name} )
  end

  def test_each
    @zipFile.each {
      |entry|
      assert_equals(nextTestEntryName, entry.name)
    }
    assert_equals(4, @testEntryNameIndex)
  end

  def test_foreach
    ZipFile.foreach(TestZipFile::TEST_ZIP2.zipName) {
      |entry|
      assert_equals(nextTestEntryName, entry.name)
    }
    assert_equals(4, @testEntryNameIndex)
  end

  def test_getInputStream
    @zipFile.each {
      |entry|
      assertEntry(nextTestEntryName, @zipFile.getInputStream(entry), 
		  entry.name)
    }
    assert_equals(4, @testEntryNameIndex)
  end

  def test_getInputStreamBlock
    fileAndEntryName = @zipFile.entries.first.name
    @zipFile.getInputStream(fileAndEntryName) {
      |zis|
      assertEntryContentsForStream(fileAndEntryName, 
				   zis, 
				   fileAndEntryName)
    }
  end
end

class CommonZipFileFixture < RUNIT::TestCase
  include AssertEntry

  EMPTY_FILENAME = "emptyZipFile.zip"

  TEST_ZIP = TestZipFile::TEST_ZIP2.clone
  TEST_ZIP.zipName = "4entry_copy.zip"

  def setup
    File.delete(EMPTY_FILENAME) if File.exists?(EMPTY_FILENAME)
    File.copy(TestZipFile::TEST_ZIP2.zipName, TEST_ZIP.zipName)
  end
end

class ZipFileTest < CommonZipFileFixture

  def test_createFromScratch
    comment  = "a short comment"

    zf = ZipFile.new(EMPTY_FILENAME, ZipFile::CREATE)
    zf.comment = comment
    zf.close

    zfRead = ZipFile.new(EMPTY_FILENAME)
    assert_equals(comment, zfRead.comment)
    assert_equals(0, zfRead.entries.length)
  end

  def test_add
    srcFile   = "ziptest.rb"
    entryName = "newEntryName.rb" 
    assert(File.exists? srcFile)
    zf = ZipFile.new(EMPTY_FILENAME, ZipFile::CREATE)
    zf.add(entryName, srcFile)
    zf.close

    zfRead = ZipFile.new(EMPTY_FILENAME)
    assert_equals("", zfRead.comment)
    assert_equals(1, zfRead.entries.length)
    assert_equals(entryName, zfRead.entries.first.name)
    AssertEntry.assertContents(srcFile, zfRead.getInputStream(entryName).read)
  end

  def test_addExistingEntryName
    assert_exception(ZipEntryExistsError) {
      ZipFile.open(TEST_ZIP.zipName) {
	|zf|
	zf.add(zf.entries.first.name, "ziptest.rb")
      }
    }
  end

  def test_addExistingEntryNameReplace
    gotCalled = false
    replacedEntry = nil
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      replacedEntry = zf.entries.first.name
      zf.add(replacedEntry, "ziptest.rb") { gotCalled = true; true }
    }
    assert(gotCalled)
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      assertContains(zf, replacedEntry, "ziptest.rb")
    }
  end

  def test_addDirectory
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      zf.add(TestFiles::EMPTY_TEST_DIR, TestFiles::EMPTY_TEST_DIR)
    }
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      dirEntry = zf.entries.detect { |e| e == TestFiles::EMPTY_TEST_DIR+"/" } 
      assert(dirEntry != nil)
      assert(dirEntry.isDirectory)
    }
  end

  def test_remove
    entryToRemove, *remainingEntries = TEST_ZIP.entryNames

    File.copy(TestZipFile::TEST_ZIP2.zipName, TEST_ZIP.zipName)

    zf = ZipFile.new(TEST_ZIP.zipName)
    assert(zf.entries.map { |e| e.name }.include?(entryToRemove))
    zf.remove(entryToRemove)
    assert(! zf.entries.map { |e| e.name }.include?(entryToRemove))
    assert_equals(zf.entries.map {|x| x.name }.sort, remainingEntries.sort) 
    zf.close

    zfRead = ZipFile.new(TEST_ZIP.zipName)
    assert(! zfRead.entries.map { |e| e.name }.include?(entryToRemove))
    assert_equals(zfRead.entries.map {|x| x.name }.sort, remainingEntries.sort) 
    zfRead.close
  end


  def test_rename
    entryToRename, *remainingEntries = TEST_ZIP.entryNames
    
    zf = ZipFile.new(TEST_ZIP.zipName)
    assert(zf.entries.map { |e| e.name }.include?  entryToRename)
    
    newName = "changed name"
    assert(! zf.entries.map { |e| e.name }.include?(newName))

    zf.rename(entryToRename, newName)
    assert(zf.entries.map { |e| e.name }.include?  newName)

    zf.close

    zfRead = ZipFile.new(TEST_ZIP.zipName)
    assert(zfRead.entries.map { |e| e.name }.include?  newName)
    zfRead.close
  end

  def test_renameToExistingEntry
    oldEntries = nil
    ZipFile.open(TEST_ZIP.zipName) { |zf| oldEntries = zf.entries }

    assert_exception(ZipEntryExistsError) {
      ZipFile.open(TEST_ZIP.zipName) {
	|zf|
	zf.rename(zf.entries[0], zf.entries[1].name)
      }
    }

    ZipFile.open(TEST_ZIP.zipName) { 
      |zf| 
      assert_equals(oldEntries.map{ |e| e.name }, zf.entries.map{ |e| e.name })
    }
  end

  def test_renameToExistingEntryOverwrite
    oldEntries = nil
    ZipFile.open(TEST_ZIP.zipName) { |zf| oldEntries = zf.entries }
    
    gotCalled = false
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      zf.rename(zf.entries[0], zf.entries[1].name) { gotCalled = true; true }
    }

    assert(gotCalled)
    oldEntries.delete_at(0)
    ZipFile.open(TEST_ZIP.zipName) { 
      |zf| 
      assert_equals(oldEntries.map{ |e| e.name }, 
		    zf.entries.map{ |e| e.name })
    }
  end

  def test_renameNonEntry
    nonEntry = "bogusEntry"
    targetEntry = "targetEntryName"
    zf = ZipFile.new(TEST_ZIP.zipName)
    assert(! zf.entries.include?(nonEntry))
    assert_exception(ZipNoSuchEntryError) {
      zf.rename(nonEntry, targetEntry)
    }
    zf.commit
    assert(! zf.entries.include?(targetEntry))
  ensure
    zf.close
  end

  def test_renameEntryToExistingEntry
    entry1, entry2, *remaining = TEST_ZIP.entryNames
    zf = ZipFile.new(TEST_ZIP.zipName)
    assert_exception(ZipEntryExistsError) {
      zf.rename(entry1, entry2)
    }
  ensure 
    zf.close
  end

  def test_replace
    unchangedEntries = TEST_ZIP.entryNames.dup
    entryToReplace = unchangedEntries.delete_at(2)
    newEntrySrcFilename = "ziptest.rb" 

    zf = ZipFile.new(TEST_ZIP.zipName)
    zf.replace(entryToReplace, newEntrySrcFilename)
    
    zf.close

    zfRead = ZipFile.new(TEST_ZIP.zipName)
    AssertEntry::assertContents(newEntrySrcFilename, 
				zfRead.getInputStream(entryToReplace).read)
    zfRead.close    
  end

  def test_replaceNonEntry
    entryToReplace = "nonExistingEntryname"
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      assert_exception(ZipNoSuchEntryError) {
	zf.replace(entryToReplace, "ziptest.rb")
      }
    }
  end

  def test_commit
    newName = "renamedFirst"
    zf = ZipFile.new(TEST_ZIP.zipName)
    oldName = zf.entries.first
    zf.rename(oldName, newName)
    zf.commit

    zfRead = ZipFile.new(TEST_ZIP.zipName)
    assert(zfRead.entries.detect { |e| e.name == newName } != nil)
    assert(zfRead.entries.detect { |e| e.name == oldName } == nil)
    zfRead.close

    zf.close
  end

  # This test tests that after commit, you
  # can delete the file you used to add the entry to the zip file
  # with
  def test_commitUseZipEntry
    File.copy(TestFiles::RANDOM_ASCII_FILE1, "okToDelete.txt")
    zf = ZipFile.open(TEST_ZIP.zipName)
    zf.add("okToDelete.txt", "okToDelete.txt")
    assertContains(zf, "okToDelete.txt")
    zf.commit
    File.move("okToDelete.txt", "okToDeleteMoved.txt")
    assertContains(zf, "okToDelete.txt", "okToDeleteMoved.txt")
  end

#  def test_close
#    zf = ZipFile.new(TEST_ZIP.zipName)
#    zf.close
#    assert_exception(IOError) {
#      zf.extract(TEST_ZIP.entryNames.first, "hullubullu")
#    }
#  end

  def test_compound1
    renamedName = "renamedName"
    originalEntries = []
    begin
      zf = ZipFile.new(TEST_ZIP.zipName)
      originalEntries = zf.entries.dup

      assertNotContains(zf, TestFiles::RANDOM_ASCII_FILE1)
      zf.add(TestFiles::RANDOM_ASCII_FILE1, 
	     TestFiles::RANDOM_ASCII_FILE1)
      assertContains(zf, TestFiles::RANDOM_ASCII_FILE1)

      zf.rename(zf.entries[0], renamedName)
      assertContains(zf, renamedName)

      TestFiles::BINARY_TEST_FILES.each {
	|filename|
	zf.add(filename, filename)
	assertContains(zf, filename)
      }

      assertContains(zf, originalEntries.last.to_s)
      zf.remove(originalEntries.last.to_s)
      assertNotContains(zf, originalEntries.last.to_s)
      
    ensure
      zf.close
    end
    begin
      zfRead = ZipFile.new(TEST_ZIP.zipName)
      assertContains(zfRead, TestFiles::RANDOM_ASCII_FILE1)
      assertContains(zfRead, renamedName)
      TestFiles::BINARY_TEST_FILES.each {
	|filename|
	assertContains(zfRead, filename)
      }
      assertNotContains(zfRead, originalEntries.last.to_s)
    ensure
      zfRead.close
    end
  end

  def test_compound2
    begin
      zf = ZipFile.new(TEST_ZIP.zipName)
      originalEntries = zf.entries.dup
      
      originalEntries.each {
	|entry|
	zf.remove(entry)
	assertNotContains(zf, entry)
      }
      assert(zf.entries.empty?)
      
      TestFiles::ASCII_TEST_FILES.each {
	|filename|
	zf.add(filename, filename)
	assertContains(zf, filename)
      }
      assert_equals(zf.entries.map { |e| e.name }, TestFiles::ASCII_TEST_FILES)
      
      zf.rename(TestFiles::ASCII_TEST_FILES[0], "newName")
      assertNotContains(zf, TestFiles::ASCII_TEST_FILES[0])
      assertContains(zf, "newName")
    ensure
      zf.close
    end
    begin
      zfRead = ZipFile.new(TEST_ZIP.zipName)
      asciiTestFiles = TestFiles::ASCII_TEST_FILES.dup
      asciiTestFiles.shift
      asciiTestFiles.each {
	|filename|
	assertContains(zf, filename)
      }

      assertContains(zf, "newName")
    ensure
      zfRead.close
    end
  end

  private
  def assertContains(zf, entryName, filename = entryName)
    assert(zf.entries.detect { |e| e.name == entryName} != nil, "entry #{entryName} not in #{zf.entries.join(', ')} in zip file #{zf}")
    assertEntryContents(zf, entryName, filename) if File.exists?(filename)
  end
  
  def assertNotContains(zf, entryName)
    assert(zf.entries.detect { |e| e.name == entryName} == nil, "entry #{entryName} in #{zf.entries.join(', ')} in zip file #{zf}")
  end
end


class ZipFileExtractTest < CommonZipFileFixture
  EXTRACTED_FILENAME = "extEntry"
  ENTRY_TO_EXTRACT, *REMAINING_ENTRIES = TEST_ZIP.entryNames.reverse

  def setup
    super
    File.delete(EXTRACTED_FILENAME) if File.exists?(EXTRACTED_FILENAME)
  end

  def test_extract
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      zf.extract(ENTRY_TO_EXTRACT, EXTRACTED_FILENAME)
      
      assert(File.exists? EXTRACTED_FILENAME)
      AssertEntry::assertContents(EXTRACTED_FILENAME, 
				  zf.getInputStream(ENTRY_TO_EXTRACT).read)
    }
  end

  def test_extractExists
    writtenText = "written text"
    File.open(EXTRACTED_FILENAME, "w") { |f| f.write(writtenText) }

    assert_exception(ZipDestinationFileExistsError) {
      ZipFile.open(TEST_ZIP.zipName) { 
	|zf| 
	zf.extract(zf.entries.first, EXTRACTED_FILENAME) 
      }
    }
    File.open(EXTRACTED_FILENAME, "r") {
      |f|
      assert_equals(writtenText, f.read)
    }
  end

  def test_extractExistsOverwrite
    writtenText = "written text"
    File.open(EXTRACTED_FILENAME, "w") { |f| f.write(writtenText) }

    gotCalled = false
    ZipFile.open(TEST_ZIP.zipName) {
      |zf|
      zf.extract(zf.entries.first, EXTRACTED_FILENAME) { gotCalled = true; true }
    }

    assert(gotCalled)
    File.open(EXTRACTED_FILENAME, "r") {
      |f|
      assert(writtenText != f.read)
    }
  end

  def test_extractNonEntry
    zf = ZipFile.new(TEST_ZIP.zipName)
    assert_exception(ZipNoSuchEntryError) { zf.extract("nonExistingEntry", "nonExistingEntry") }
  ensure
    zf.close if zf
  end

  def test_extractNonEntry2
    outFile = "outfile"
    assert_exception(ZipNoSuchEntryError) {
      zf = ZipFile.new(TEST_ZIP.zipName)
      nonEntry = "hotdog-diddelidoo"
      assert(! zf.entries.include?(nonEntry))
      zf.extract(nonEntry, outFile)
      zf.close
    }
    assert(! File.exists?(outFile))
  end

end


TestZipFile::createTestZips(ARGV.index("recreate") != nil)
TestFiles::createTestFiles(ARGV.index("recreate") != nil)

# Copyright (C) 2002 Thomas Sondergaard
# rubyzip is free software; you can redistribute it and/or
# modify it under the terms of the ruby license.
