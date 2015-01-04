---
layout: page
title: The sum of n
---

Let's compute the sum of $$n$$
$$\sum_{n>0}n$$
For this computation let's add a small imaginary perturbation to the exponent

$$\sum_{n>0}{n^{1+\epsilon{}i}}$$

It yields:
$$\sum_{n>0}e^{(1+\epsilon{}i)\ln(n)} = \sum_{n>0}ne^{\epsilon{}\ln(n)i}$$

$$M = \left( \begin{smallmatrix}
  \vdots & \vdots &  & \vdots\\
  a_1 & a_2 & \cdots & a_n\\
  \vdots & \vdots &  & \vdots
\end{smallmatrix} \right)
\cdot
\left( \begin{smallmatrix}
  \dots & b_1 & \dots\\
  \dots & b_2 & \dots\\
   & \vdots & \\
  \dots & b_n & \dots\\
\end{smallmatrix} \right)
$$


