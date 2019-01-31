/*********************************************************************
* Software License Agreement (BSD License)
*
*  Copyright (c) 2019, Bielefeld University
*  All rights reserved.
*
*  Redistribution and use in source and binary forms, with or without
*  modification, are permitted provided that the following conditions
*  are met:
*
*   * Redistributions of source code must retain the above copyright
*     notice, this list of conditions and the following disclaimer.
*   * Redistributions in binary form must reproduce the above
*     copyright notice, this list of conditions and the following
*     disclaimer in the documentation and/or other materials provided
*     with the distribution.
*   * Neither the name  of Bielefeld University nor the names of its
*     contributors may be used to endorse or promote products derived
*     from this software without specific prior written permission.
*
*  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
*  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
*  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
*  FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
*  COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
*  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
*  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
*  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
*  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
*  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
*  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
*  POSSIBILITY OF SUCH DAMAGE.
*********************************************************************/

/* Author: Robert Haschke */
/* Desc: dummy file just to validate moveit_ci's checking capabilities */

#include <gtest/gtest.h>
#include <memory>

namespace moveit { namespace core {
class RobotModel;
} }

class TestClass : public testing::Test {
protected:
  void SetUp() {}
  void TearDown() override {}

  void camelCaseMethod(double *pointer, double &reference,
                       const int *const_pointer, const int &const_reference);

  int member_;
  int member_missing_trailing_underscore;
  const int const_member_;
};

void TestClass::camelCaseMethod(double* pointer, double& reference, const int* const_pointer, const int& const_reference)
{
  *pointer = *const_pointer;
  reference = const_reference;

  std::vector<int> VECTOR;
  for (int i=0; i != VECTOR.size(); ++i)
    ++VECTOR[i];
}

TEST(DummyTest, success) { EXPECT_TRUE(true); }

int main(int argc, char **argv) {
  testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
